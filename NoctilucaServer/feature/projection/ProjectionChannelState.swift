//
//  ProjectionChannelState.swift
//  NoctilucaServer
//
//  Created by Codex on 2/12/26.
//

import Foundation
@preconcurrency import Combine
import CoreGraphics

import SiriusKit

actor ProjectionChannelState {
    enum SessionKind {
        case video
        case audio
    }

    enum LifecycleState {
        case active
        case destroying
        case destroyed
    }

    struct AppStreamSessionInfo {
        let streamId: UUID
        let bundleId: String
        let pid: pid_t
        let flags: AppStreamFlags
        let windowSubscriptionId: UUID
        let appTerminationSubscriptionId: UUID
        /// AppStream 전용 가상 디스플레이 핸들. `nil`이면 fallback(메인 디스플레이)으로 운영된다.
        let virtualDisplayHandle: NOCVirtualDisplayHandle?
    }

    struct AccessibilitySubscriptionInfo {
        let subscriptionId: UUID
        let pid: pid_t
        let rootNodeId: UUID?
        let eventMask: AccessibilityUpdateType
        let maxDepth: UInt32
        /// `DesktopContextManager.subscribeMenuEvents`가 반환한 메뉴 핸들러 UUID.
        /// Unsubscribe 시 반드시 해제해야 한다.
        let menuEventHandlerId: UUID
    }

    struct DestroySnapshot {
        let videoSessions: [ProjectionSession]
        let audioSessions: [AudioProjectionSession]
        let dataChannels: [ProjectionDataChannel]
        let cursorSubscription: CursorEventSubscription?
        let displaySubscription: DisplayEventSubscription?
        let appEventSubscriptionId: UUID?
        let appStreamSession: AppStreamSessionInfo?
        let accessibilitySubscriptions: [AccessibilitySubscriptionInfo]
        let virtualDisplayHandles: [NOCVirtualDisplayHandle]
    }

    struct TerminationTargets {
        let videoSession: ProjectionSession?
        let audioSession: AudioProjectionSession?
        let dataChannel: ProjectionDataChannel?
    }

    enum DisplaySubscriptionInstallResult {
        case installed(previous: DisplayEventSubscription?)
        case rejected
    }

    enum DisplayUnsubscribeResult {
        case notFound
        case mismatchedSubscriptionID
        case unsubscribed(DisplayEventSubscription)
    }

    private(set) var lifecycleState: LifecycleState = .active

    private var sessions: [UUID: ProjectionSession] = [:]
    private var audioSessions: [UUID: AudioProjectionSession] = [:]
    private var projectionDataChannels: [UUID: ProjectionDataChannel] = [:]
    private var reservations: [UUID: SessionKind] = [:]
    private var sessionDisplayIDs: [UUID: CGDirectDisplayID] = [:]

    private var cursorSubscription: CursorEventSubscription?
    private var displaySubscription: DisplayEventSubscription?

    private var appEventSubscriptionId: UUID?
    private var appStreamSession: AppStreamSessionInfo?
    private var accessibilitySubscriptions: [UUID: AccessibilitySubscriptionInfo] = [:]

    /// 클라이언트가 보낸 wire UUID → 서버 VD handle 매핑.
    /// VirtualDisplayCreate 시 등록, VirtualDisplayDestroy 또는 채널 destroy 시 회수한다.
    private var virtualDisplayHandles: [UUID: NOCVirtualDisplayHandle] = [:]

    /// `DisplayLayoutManager.displayChangeSubject` 구독. 채널 수명과 동일.
    private var displayChangesCancellable: AnyCancellable?

    func reserveSession(identifier: UUID, kind: SessionKind) -> Bool {
        guard lifecycleState == .active else {
            return false
        }

        guard !isIdentifierInUse(identifier) else {
            return false
        }

        reservations[identifier] = kind
        return true
    }

    func registerPendingDataChannel(identifier: UUID, channel: ProjectionDataChannel) -> Bool {
        guard lifecycleState == .active else {
            return false
        }

        guard reservations[identifier] != nil else {
            return false
        }

        projectionDataChannels[identifier] = channel
        return true
    }

    func activateVideoSession(identifier: UUID, session: ProjectionSession, displayID: CGDirectDisplayID? = nil) -> Bool {
        guard lifecycleState == .active else {
            return false
        }

        guard reservations[identifier] == .video else {
            return false
        }

        sessions[identifier] = session
        reservations.removeValue(forKey: identifier)

        if let displayID {
            sessionDisplayIDs[identifier] = displayID
        }

        return true
    }

    func activateAudioSession(identifier: UUID, session: AudioProjectionSession) -> Bool {
        guard lifecycleState == .active else {
            return false
        }

        guard reservations[identifier] == .audio else {
            return false
        }

        audioSessions[identifier] = session
        reservations.removeValue(forKey: identifier)

        return true
    }

    func terminateByControlMessage(identifier: UUID, kind: SessionKind) -> TerminationTargets {
        switch kind {
        case .video:
            let videoSession = sessions.removeValue(forKey: identifier)
            sessionDisplayIDs.removeValue(forKey: identifier)

            if reservations[identifier] == .video {
                reservations.removeValue(forKey: identifier)
            }

            let dataChannel = takeDataChannelIfUnused(identifier: identifier)
            return TerminationTargets(videoSession: videoSession, audioSession: nil, dataChannel: dataChannel)

        case .audio:
            let audioSession = audioSessions.removeValue(forKey: identifier)

            if reservations[identifier] == .audio {
                reservations.removeValue(forKey: identifier)
            }

            let dataChannel = takeDataChannelIfUnused(identifier: identifier)
            return TerminationTargets(videoSession: nil, audioSession: audioSession, dataChannel: dataChannel)
        }
    }

    func terminateByDataChannelClosure(identifier: UUID) -> TerminationTargets {
        let dataChannel = projectionDataChannels.removeValue(forKey: identifier)
        let videoSession = sessions.removeValue(forKey: identifier)
        let audioSession = audioSessions.removeValue(forKey: identifier)

        reservations.removeValue(forKey: identifier)
        sessionDisplayIDs.removeValue(forKey: identifier)

        return TerminationTargets(videoSession: videoSession, audioSession: audioSession, dataChannel: dataChannel)
    }

    func sessionForPerformanceReport(identifier: UUID) -> ProjectionSession? {
        sessions[identifier]
    }

    func videoSessionIdentifiers(forDisplayID displayID: CGDirectDisplayID) -> [UUID] {
        sessionDisplayIDs.filter { $0.value == displayID }.map { $0.key }
    }

    func addCursorSubscriptionIfAbsent(_ subscription: CursorEventSubscription) -> Bool {
        guard lifecycleState == .active else {
            return false
        }

        guard cursorSubscription == nil else {
            return false
        }

        cursorSubscription = subscription
        return true
    }

    func isCurrentCursorSubscription(_ subscription: CursorEventSubscription) -> Bool {
        cursorSubscription === subscription
    }

    func removeCursorSubscription() -> CursorEventSubscription? {
        let subscription = cursorSubscription
        cursorSubscription = nil
        return subscription
    }

    func replaceDisplaySubscription(_ subscription: DisplayEventSubscription) -> DisplaySubscriptionInstallResult {
        guard lifecycleState == .active else {
            return .rejected
        }

        let previous = displaySubscription
        displaySubscription = subscription

        return .installed(previous: previous)
    }

    func isCurrentDisplaySubscription(_ subscription: DisplayEventSubscription) -> Bool {
        displaySubscription === subscription
    }

    func unsubscribeDisplaySubscription(expectedID: UUID) -> DisplayUnsubscribeResult {
        guard let subscription = displaySubscription else {
            return .notFound
        }

        guard subscription.id == expectedID else {
            return .mismatchedSubscriptionID
        }

        displaySubscription = nil
        return .unsubscribed(subscription)
    }

    // MARK: - App Event Subscription

    func setAppEventSubscription(id: UUID) -> Bool {
        guard lifecycleState == .active else { return false }
        appEventSubscriptionId = id
        return true
    }

    func removeAppEventSubscription() -> UUID? {
        let id = appEventSubscriptionId
        appEventSubscriptionId = nil
        return id
    }

    // MARK: - AppStream Session

    func activateAppStreamSession(_ session: AppStreamSessionInfo) -> Bool {
        guard lifecycleState == .active else { return false }
        guard appStreamSession == nil else { return false }
        appStreamSession = session
        return true
    }

    func currentAppStreamSession() -> AppStreamSessionInfo? {
        appStreamSession
    }

    func removeAppStreamSession(streamId: UUID) -> AppStreamSessionInfo? {
        guard appStreamSession?.streamId == streamId else { return nil }
        let session = appStreamSession
        appStreamSession = nil
        return session
    }

    func removeAppStreamSessionForTerminatedApp(bundleId: String) -> AppStreamSessionInfo? {
        guard appStreamSession?.bundleId == bundleId else { return nil }
        let session = appStreamSession
        appStreamSession = nil
        return session
    }

    // MARK: - Accessibility Subscriptions

    func addAccessibilitySubscription(_ info: AccessibilitySubscriptionInfo) -> Bool {
        guard lifecycleState == .active else { return false }
        accessibilitySubscriptions[info.subscriptionId] = info
        return true
    }

    func removeAccessibilitySubscription(id: UUID) -> AccessibilitySubscriptionInfo? {
        return accessibilitySubscriptions.removeValue(forKey: id)
    }

    func allAccessibilitySubscriptions() -> [AccessibilitySubscriptionInfo] {
        return Array(accessibilitySubscriptions.values)
    }

    func accessibilitySubscriptions(forPid pid: pid_t) -> [AccessibilitySubscriptionInfo] {
        return accessibilitySubscriptions.values.filter { $0.pid == pid }
    }

    // MARK: - Destroy

    func beginDestroy() -> DestroySnapshot? {
        guard lifecycleState == .active else {
            return nil
        }

        lifecycleState = .destroying

        let snapshot = DestroySnapshot(
            videoSessions: Array(sessions.values),
            audioSessions: Array(audioSessions.values),
            dataChannels: Array(projectionDataChannels.values),
            cursorSubscription: cursorSubscription,
            displaySubscription: displaySubscription,
            appEventSubscriptionId: appEventSubscriptionId,
            appStreamSession: appStreamSession,
            accessibilitySubscriptions: Array(accessibilitySubscriptions.values),
            virtualDisplayHandles: Array(virtualDisplayHandles.values)
        )

        sessions.removeAll()
        audioSessions.removeAll()
        projectionDataChannels.removeAll()
        reservations.removeAll()
        sessionDisplayIDs.removeAll()
        virtualDisplayHandles.removeAll()
        accessibilitySubscriptions.removeAll()

        cursorSubscription = nil
        displaySubscription = nil
        appEventSubscriptionId = nil
        appStreamSession = nil

        return snapshot
    }

    func completeDestroy() {
        lifecycleState = .destroyed

        displayChangesCancellable?.cancel()
        displayChangesCancellable = nil
    }

    /// `DisplayLayoutManager` 의 disconnect 이벤트를 구독해 `callback` 으로 라우팅합니다.
    /// 이 메서드는 채널 수명 동안 **정확히 한 번** 호출되어야 합니다 (ProjectionChannel.init 에서).
    /// Combine sink 는 `AnyCancellable` 로 actor 내부에 보관하여 Sendable 을 만족시킵니다.
    func installDisplayDisconnectSink(
        _ callback: @escaping @Sendable (CGDirectDisplayID) -> Void
    ) async {
        self.displayChangesCancellable = await (Task { @MainActor in
            DisplayLayoutManager.shared.displayChangeSubject
                .filter { $0.eventType.contains(.disconnected) }
                .sink { event in
                    callback(event.displayID)
                }
        }).value
    }

    // MARK: - Virtual Display Registry

    /// 주어진 wire UUID 목록 중 이미 등록되어 있거나 목록 내부에서 중복되는 첫 번째 UUID를 반환한다.
    func virtualDisplayIdentifierConflict(in candidates: [UUID]) -> UUID? {
        var seen: Set<UUID> = []
        for id in candidates {
            if virtualDisplayHandles[id] != nil { return id }
            if !seen.insert(id).inserted { return id }
        }
        return nil
    }

    /// 채널 lifecycle이 active이고 externalID가 비어 있을 때만 등록한다.
    func registerVirtualDisplay(externalID: UUID, handle: NOCVirtualDisplayHandle) -> Bool {
        guard lifecycleState == .active else { return false }
        guard virtualDisplayHandles[externalID] == nil else { return false }

        virtualDisplayHandles[externalID] = handle
        return true
    }

    /// externalID로 등록된 핸들을 꺼내고 레지스트리에서 제거한다.
    func takeVirtualDisplay(externalID: UUID) -> NOCVirtualDisplayHandle? {
        return virtualDisplayHandles.removeValue(forKey: externalID)
    }

    /// rollback 경로용. handle을 직접 받아서 일치하는 entry를 제거한다.
    func unregisterVirtualDisplay(_ handle: NOCVirtualDisplayHandle) {
        for (externalID, registered) in virtualDisplayHandles where registered === handle {
            virtualDisplayHandles.removeValue(forKey: externalID)
            return
        }
    }

    /// 주어진 CGDirectDisplayID에 대응하는 wire UUID를 반환한다. (DisplayInfo.virtualDisplayIdentifier 채우기용)
    func virtualDisplayExternalID(forDisplayID displayID: CGDirectDisplayID) -> UUID? {
        for (externalID, handle) in virtualDisplayHandles where handle.displayID == displayID {
            return externalID
        }
        return nil
    }

    private func isIdentifierInUse(_ identifier: UUID) -> Bool {
        sessions[identifier] != nil ||
        audioSessions[identifier] != nil ||
        reservations[identifier] != nil ||
        projectionDataChannels[identifier] != nil
    }

    private func takeDataChannelIfUnused(identifier: UUID) -> ProjectionDataChannel? {
        let hasLiveSession = sessions[identifier] != nil || audioSessions[identifier] != nil
        let hasReservation = reservations[identifier] != nil

        guard !hasLiveSession && !hasReservation else {
            return nil
        }

        return projectionDataChannels.removeValue(forKey: identifier)
    }
}
