//
//  AppStreamWindowManager+VDSync.swift
//  NoctilucaClient (macOS only)
//
//  AppStream 시작 시점에 클라이언트의 NSScreen 레이아웃을 호스트 가상 디스플레이로
//  복제 (VirtualDisplayCreate × N + DisplayLayoutChange × N) 하고, AppStream 종료 시
//  명시적 destroy 트랜잭션으로 회수한다. 그리고 AppStreamWindow 의 위치를 호스트
//  글로벌 좌표 ↔ 클라 NSScreen 좌표 사이에서 1:1 매핑한다.
//

#if os(macOS)

import Foundation
import AppKit
import Combine

import SiriusKitClient

extension AppStreamWindowManager {

    /// 매핑 entry: 클라 NSScreen ↔ 호스트 가상 디스플레이.
    struct HostVDMapping {
        /// 클라가 VirtualDisplayCreate 시 보낸 wire UUID.
        let wireIdentifier: UUID
        /// 호스트가 할당한 CGDirectDisplayID (DisplayInfo.displayID).
        let hostDisplayID: UInt32
        /// 클라 NSScreen 의 displayID.
        let clientDisplayID: CGDirectDisplayID
        /// 호스트 글로벌 좌표계의 VD frame (top-left).
        let hostFrame: CGRect
        /// 클라 NSScreen 의 frame (Cocoa bottom-left).
        let clientCocoaFrame: CGRect
    }

    // MARK: - Provisioning

    /// AppStream 시작 직전에 호출. 클라 NSScreen 레이아웃을 호스트로 복제한다.
    /// 실패해도 throw 하지 않고 매핑 없이 진행 — fallback path 에서 서버가 단일 VD 자동 생성.
    func provisionHostVirtualDisplays(
        projectionChannel: ProjectionChannel
    ) async {
        // 항상 최신 NSScreen 스냅샷에서 출발.
        LocalDisplayLayoutManager.shared.startMonitoring()
        let localScreens = LocalDisplayLayoutManager.shared.snapshot()

        guard !localScreens.isEmpty else {
            logger.warning("provisionHostVirtualDisplays: no local screens; skipping")
            return
        }

        // 1) VirtualDisplayCreate × N 트랜잭션
        var pendingMappings: [(wireIdentifier: UUID, clientScreen: LocalScreenInfo)] = []
        var createOps: [DisplayOperation] = []

        for (_, screen) in localScreens {
            let identifier = UUID()
            pendingMappings.append((wireIdentifier: identifier, clientScreen: screen))

            let spec = DisplaySpec(
                resolution: SRSize(
                    width: Double(screen.frame.width),
                    height: Double(screen.frame.height)
                ),
                refreshRate: 60,
                scaleFactor: 1,
                metadata: [:]
            )
            createOps.append(DisplayOperation(operation: .createVirtualDisplay(VirtualDisplayCreate(
                identifier: identifier,
                desiredSpecs: [spec],
                purpose: "appStream",
                metadata: [:]
            ))))
        }

        do {
            let createResp = try await projectionChannel.requestDisplayTransaction(operations: createOps)
            guard createResp.isSuccess else {
                logger.warning("provisionHostVirtualDisplays: create transaction rejected: \(createResp.reason ?? "no reason")")
                return
            }
        } catch {
            logger.warning("provisionHostVirtualDisplays: create transaction failed: \(error)")
            return
        }

        // 2) wire UUID → host displayID 매핑 학습.
        //    nocvirtdisplay 가 spawn 된 직후엔 macOS WindowServer 에 아직 등록 전이라
        //    DisplayList 에 안 잡힐 수 있다. 짧은 backoff 로 재조회한다.
        let mappings = await learnVDMappings(
            pendingMappings: pendingMappings,
            projectionChannel: projectionChannel
        )

        guard !mappings.isEmpty else {
            logger.warning("provisionHostVirtualDisplays: no VD-to-display mappings learned after retries")
            return
        }

        // 3) origin change × N + mainDisplayID 트랜잭션 (호스트 VD 들의 origin 을
        //    클라 NSScreen 의 X11 origin 으로 설정).
        var changeOps: [DisplayOperation] = []
        var primaryHostID: UInt32?

        for (clientID, mapping) in mappings {
            guard let screen = localScreens[clientID] else { continue }

            let origin = SRPoint(
                x: Double(screen.x11Frame.origin.x),
                y: Double(screen.x11Frame.origin.y)
            )
            changeOps.append(DisplayOperation(operation: .change(DisplayLayoutChange(
                displayID: UInt32(mapping.hostDisplayID),
                spec: nil,
                rotation: nil,
                origin: origin
            ))))

            if screen.isPrimary {
                primaryHostID = mapping.hostDisplayID
            }
        }

        do {
            let changeResp = try await projectionChannel.requestDisplayTransaction(
                operations: changeOps,
                mainDisplayID: primaryHostID
            )
            if !changeResp.isSuccess {
                logger.warning("provisionHostVirtualDisplays: layout transaction rejected: \(changeResp.reason ?? "no reason")")
            }
        } catch {
            logger.warning("provisionHostVirtualDisplays: layout transaction failed: \(error)")
        }

        // 4) 매핑 + 식별자 + 마지막 동기화 스냅샷 보관.
        self.hostVDMappings = mappings
        self.createdVDIdentifiers = pendingMappings.map { $0.wireIdentifier }
        self.lastSyncedLocalScreens = localScreens

        logger.info("provisionHostVirtualDisplays: provisioned \(mappings.count) VD(s); primary host displayID=\(primaryHostID.map { String($0) } ?? "none")")

        // 5) 실시간 동기화 구독 시작.
        startLocalDisplayChangeObservation(projectionChannel: projectionChannel)
    }

    /// AppStream 종료 시점에 호출. 클라가 만든 VD 들을 명시적으로 destroy.
    /// 서버에 cleanup 안전망이 있으므로 실패해도 무시한다.
    func unprovisionHostVirtualDisplays(
        projectionChannel: ProjectionChannel
    ) async {
        // 실시간 동기화 구독 먼저 해제 (race 방지).
        localDisplayChangeCancellable?.cancel()
        localDisplayChangeCancellable = nil

        guard !createdVDIdentifiers.isEmpty else {
            self.lastSyncedLocalScreens.removeAll()
            return
        }

        let destroyOps: [DisplayOperation] = createdVDIdentifiers.map { id in
            DisplayOperation(operation: .destroyVirtualDisplay(VirtualDisplayDestroy(identifier: id)))
        }

        do {
            _ = try await projectionChannel.requestDisplayTransaction(operations: destroyOps)
        } catch {
            logger.warning("unprovisionHostVirtualDisplays: destroy transaction failed: \(error). Server will clean up.")
        }

        self.createdVDIdentifiers.removeAll()
        self.hostVDMappings.removeAll()
        self.lastSyncedLocalScreens.removeAll()
    }

    // MARK: - Realtime Sync

    /// `LocalDisplayLayoutManager.displayLayoutChangeSubject` 를 구독해 NSScreen
    /// 변경을 호스트 VD pool 에 incremental 하게 반영한다.
    private func startLocalDisplayChangeObservation(
        projectionChannel: ProjectionChannel
    ) {
        localDisplayChangeCancellable?.cancel()

        localDisplayChangeCancellable = LocalDisplayLayoutManager.shared
            .displayLayoutChangeSubject
            .sink { [weak self] newLayouts in
                guard let self else { return }
                Task { @MainActor in
                    await self.handleLocalDisplayChange(
                        newLayouts: newLayouts,
                        projectionChannel: projectionChannel
                    )
                }
            }
    }

    /// NSScreen 스냅샷 갱신을 받았을 때 호출. 직전 스냅샷과 diff 해서
    /// 추가/제거/변경된 디스플레이를 별도 트랜잭션들로 호스트에 반영한다.
    private func handleLocalDisplayChange(
        newLayouts: [CGDirectDisplayID: LocalScreenInfo],
        projectionChannel: ProjectionChannel
    ) async {
        let oldIDs = Set(lastSyncedLocalScreens.keys)
        let newIDs = Set(newLayouts.keys)

        let removedIDs = oldIDs.subtracting(newIDs)
        let addedIDs = newIDs.subtracting(oldIDs)
        let stillPresentIDs = oldIDs.intersection(newIDs)

        // 변경 (해상도 / origin / primary 여부) 감지.
        var modifiedIDs: Set<CGDirectDisplayID> = []
        for id in stillPresentIDs {
            guard let old = lastSyncedLocalScreens[id], let new = newLayouts[id] else { continue }
            if old.resolution != new.resolution
                || old.scaleFactor != new.scaleFactor
                || old.refreshRate != new.refreshRate
                || old.x11Frame != new.x11Frame
                || old.isPrimary != new.isPrimary {
                modifiedIDs.insert(id)
            }
        }

        if removedIDs.isEmpty && addedIDs.isEmpty && modifiedIDs.isEmpty {
            return
        }

        logger.info("handleLocalDisplayChange: removed=\(removedIDs.count) added=\(addedIDs.count) modified=\(modifiedIDs.count)")

        // (1) 사라진 NSScreen → VirtualDisplayDestroy.
        if !removedIDs.isEmpty {
            var destroyOps: [DisplayOperation] = []
            var removedWireIdentifiers: [UUID] = []
            for id in removedIDs {
                guard let mapping = hostVDMappings[id] else { continue }
                destroyOps.append(DisplayOperation(operation:
                    .destroyVirtualDisplay(VirtualDisplayDestroy(identifier: mapping.wireIdentifier))
                ))
                removedWireIdentifiers.append(mapping.wireIdentifier)
                hostVDMappings.removeValue(forKey: id)
            }
            if !destroyOps.isEmpty {
                do {
                    _ = try await projectionChannel.requestDisplayTransaction(operations: destroyOps)
                } catch {
                    logger.warning("realtime sync: destroy transaction failed: \(error)")
                }
            }
            createdVDIdentifiers.removeAll { removedWireIdentifiers.contains($0) }
        }

        // (2) 새 NSScreen → VirtualDisplayCreate + 후속 매핑 학습 + origin change.
        if !addedIDs.isEmpty {
            await provisionAddedScreens(
                screens: addedIDs.compactMap { newLayouts[$0] },
                projectionChannel: projectionChannel
            )
        }

        // (3) 변경된 NSScreen → spec / origin / mainDisplayID 갱신.
        if !modifiedIDs.isEmpty {
            await applyModifiedScreens(
                screens: modifiedIDs.compactMap { newLayouts[$0] },
                projectionChannel: projectionChannel
            )
        }

        // (4) 매핑 갱신 후 primary 가 바뀌었는지 확인. mainDisplayID 갱신만 별도 빈 트랜잭션.
        let newPrimaryHostID = hostVDMappings.values.first { mapping in
            newLayouts[mapping.clientDisplayID]?.isPrimary == true
        }?.hostDisplayID

        if let newPrimaryHostID, !addedIDs.isEmpty || !modifiedIDs.isEmpty {
            // 위 트랜잭션들에서 mainDisplayID 가 같이 set 되는 케이스도 있고
            // 아닌 케이스도 있어, 마지막에 명시적으로 한 번 더 보낸다 (no-op operations).
            do {
                _ = try await projectionChannel.requestDisplayTransaction(
                    operations: [],
                    mainDisplayID: newPrimaryHostID
                )
            } catch {
                logger.warning("realtime sync: mainDisplay transaction failed: \(error)")
            }
        }

        // (5) 마지막 동기화 스냅샷 갱신.
        lastSyncedLocalScreens = newLayouts
    }

    /// 추가된 NSScreen 들에 대응하는 VD 를 새로 spawn 하고 매핑 학습 후 origin 설정.
    private func provisionAddedScreens(
        screens: [LocalScreenInfo],
        projectionChannel: ProjectionChannel
    ) async {
        guard !screens.isEmpty else { return }

        var pending: [(wireIdentifier: UUID, clientScreen: LocalScreenInfo)] = []
        var createOps: [DisplayOperation] = []

        for screen in screens {
            let identifier = UUID()
            pending.append((wireIdentifier: identifier, clientScreen: screen))

            let spec = DisplaySpec(
                resolution: SRSize(
                    width: Double(screen.frame.width),
                    height: Double(screen.frame.height)
                ),
                refreshRate: 60,
                scaleFactor: 1,
                metadata: [:]
            )
            createOps.append(DisplayOperation(operation: .createVirtualDisplay(VirtualDisplayCreate(
                identifier: identifier,
                desiredSpecs: [spec],
                purpose: "appStream",
                metadata: [:]
            ))))
        }

        do {
            let resp = try await projectionChannel.requestDisplayTransaction(operations: createOps)
            guard resp.isSuccess else {
                logger.warning("provisionAddedScreens: create transaction rejected: \(resp.reason ?? "no reason")")
                return
            }
        } catch {
            logger.warning("provisionAddedScreens: create transaction failed: \(error)")
            return
        }

        // 매핑 학습 (retry 포함) + origin change.
        let learned = await learnVDMappings(
            pendingMappings: pending,
            projectionChannel: projectionChannel
        )

        var changeOps: [DisplayOperation] = []
        for (clientID, mapping) in learned {
            hostVDMappings[clientID] = mapping
            createdVDIdentifiers.append(mapping.wireIdentifier)

            guard let screen = pending.first(where: { $0.clientScreen.displayID == clientID })?.clientScreen else {
                continue
            }
            changeOps.append(DisplayOperation(operation: .change(DisplayLayoutChange(
                displayID: UInt32(mapping.hostDisplayID),
                spec: nil,
                rotation: nil,
                origin: SRPoint(
                    x: Double(screen.x11Frame.origin.x),
                    y: Double(screen.x11Frame.origin.y)
                )
            ))))
        }

        if !changeOps.isEmpty {
            do {
                _ = try await projectionChannel.requestDisplayTransaction(operations: changeOps)
            } catch {
                logger.warning("provisionAddedScreens: layout transaction failed: \(error)")
            }
        }
    }

    /// 변경된 NSScreen 들의 spec/origin 을 호스트 VD 에 반영.
    private func applyModifiedScreens(
        screens: [LocalScreenInfo],
        projectionChannel: ProjectionChannel
    ) async {
        guard !screens.isEmpty else { return }

        var ops: [DisplayOperation] = []
        for screen in screens {
            guard var mapping = hostVDMappings[screen.displayID] else {
                logger.warning("applyModifiedScreens: no mapping for displayID=\(screen.displayID)")
                continue
            }

            let spec = DisplaySpec(
                resolution: SRSize(
                    width: Double(screen.frame.width),
                    height: Double(screen.frame.height)
                ),
                refreshRate: 60,
                scaleFactor: 1,
                metadata: [:]
            )

            ops.append(DisplayOperation(operation: .change(DisplayLayoutChange(
                displayID: UInt32(mapping.hostDisplayID),
                spec: spec,
                rotation: nil,
                origin: SRPoint(
                    x: Double(screen.x11Frame.origin.x),
                    y: Double(screen.x11Frame.origin.y)
                )
            ))))

            // 매핑의 host frame 도 새 NSScreen 크기로 갱신 (anchor 매핑 정확도 유지).
            let newHostFrame = CGRect(
                origin: CGPoint(x: screen.x11Frame.origin.x, y: screen.x11Frame.origin.y),
                size: screen.frame.size
            )
            mapping = HostVDMapping(
                wireIdentifier: mapping.wireIdentifier,
                hostDisplayID: mapping.hostDisplayID,
                clientDisplayID: mapping.clientDisplayID,
                hostFrame: newHostFrame,
                clientCocoaFrame: screen.frame
            )
            hostVDMappings[screen.displayID] = mapping
        }

        if !ops.isEmpty {
            do {
                _ = try await projectionChannel.requestDisplayTransaction(operations: ops)
            } catch {
                logger.warning("applyModifiedScreens: transaction failed: \(error)")
            }
        }
    }

    // MARK: - Mapping Learning (with retry)

    /// VD 가 시스템에 등록되어 DisplayList 에 노출되기까지 최대 ~1.4초 동안 짧은 backoff 로 조회.
    /// 이미 학습한 매핑은 재조회하지 않고 누적한다. 매칭 안 된 wire UUID 는 그냥 누락된 채로 넘긴다 —
    /// 호출 측이 매핑 0개여도 진행할지 abort 할지 판단한다.
    private static let vdMappingMaxAttempts = 8
    private static let vdMappingDelays: [Duration] = [
        .milliseconds(50),
        .milliseconds(100),
        .milliseconds(150),
        .milliseconds(200),
        .milliseconds(250),
        .milliseconds(300),
        .milliseconds(400),
    ]

    func learnVDMappings(
        pendingMappings: [(wireIdentifier: UUID, clientScreen: LocalScreenInfo)],
        projectionChannel: ProjectionChannel
    ) async -> [CGDirectDisplayID: HostVDMapping] {
        var mappings: [CGDirectDisplayID: HostVDMapping] = [:]
        var unmatched = Set(pendingMappings.map { $0.wireIdentifier })

        for attempt in 0..<Self.vdMappingMaxAttempts where !unmatched.isEmpty {
            if attempt > 0 {
                let delay = Self.vdMappingDelays[min(attempt - 1, Self.vdMappingDelays.count - 1)]
                try? await Task.sleep(for: delay)
            }

            let displayList: DisplayListResponse
            do {
                displayList = try await projectionChannel.requestDisplayList()
            } catch {
                logger.warning("learnVDMappings: requestDisplayList failed (attempt \(attempt + 1)): \(error)")
                continue
            }

            for pending in pendingMappings where unmatched.contains(pending.wireIdentifier) {
                guard let display = displayList.displays.first(where: {
                    $0.virtualDisplayIdentifier == pending.wireIdentifier
                }) else {
                    continue
                }

                let hostFrame = CGRect(
                    x: CGFloat(display.bounds.x),
                    y: CGFloat(display.bounds.y),
                    width: CGFloat(display.bounds.width),
                    height: CGFloat(display.bounds.height)
                )
                mappings[pending.clientScreen.displayID] = HostVDMapping(
                    wireIdentifier: pending.wireIdentifier,
                    hostDisplayID: UInt32(display.displayID),
                    clientDisplayID: pending.clientScreen.displayID,
                    hostFrame: hostFrame,
                    clientCocoaFrame: pending.clientScreen.frame
                )
                unmatched.remove(pending.wireIdentifier)
            }

            if !unmatched.isEmpty {
                logger.info("learnVDMappings: \(unmatched.count) VD(s) still pending after attempt \(attempt + 1); retrying")
            }
        }

        if !unmatched.isEmpty {
            logger.warning("learnVDMappings: \(unmatched.count) VD(s) never appeared in DisplayList after \(Self.vdMappingMaxAttempts) attempts")
        }

        return mappings
    }

    // MARK: - Coordinate Mapping

    /// 호스트 글로벌 좌표 (top-left) 의 윈도우 frame 을 받아서
    /// 클라이언트 NSWindow 의 Cocoa origin (bottom-left) 을 계산한다.
    /// 매핑이 없거나 어느 VD 와도 교차하지 않으면 nil 반환 (호출 측은 기본 위치 fallback).
    func translateServerFrameToClientOrigin(serverBounds: CGRect) -> CGPoint? {
        guard !hostVDMappings.isEmpty else { return nil }

        // 윈도우의 좌상단이 어느 호스트 VD frame 에 속하는지 찾기.
        guard let mapping = hostVDMappings.values.first(where: {
            $0.hostFrame.contains(serverBounds.origin)
        }) else {
            // 좌상단이 어디에도 안 속하면 윈도우 중심으로 한 번 더 시도.
            let center = CGPoint(x: serverBounds.midX, y: serverBounds.midY)
            guard let fallback = hostVDMappings.values.first(where: {
                $0.hostFrame.contains(center)
            }) else {
                return nil
            }
            return mapToClientCocoa(serverBounds: serverBounds, mapping: fallback)
        }

        return mapToClientCocoa(serverBounds: serverBounds, mapping: mapping)
    }

    private func mapToClientCocoa(serverBounds: CGRect, mapping: HostVDMapping) -> CGPoint? {
        // 매핑된 NSScreen 의 *현재* frame 을 가져온다 (cached clientCocoaFrame 은 stale 가능).
        guard let nsScreen = NSScreen.screens.first(where: {
            $0.compatibleDisplayID == mapping.clientDisplayID
        }) else {
            return nil
        }

        return LocalDisplayLayoutManager.translateToClientCocoa(
            hostTopLeftOrigin: serverBounds.origin,
            windowSize: serverBounds.size,
            hostVDFrame: mapping.hostFrame,
            clientScreen: nsScreen
        )
    }
}

#endif
