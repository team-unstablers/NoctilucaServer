//
//  ProjectionChannel+appman.swift
//  NoctilucaServer
//

import Foundation
import CoreGraphics
import SiriusKit

import AppKit

/// AppStream 세션 내에서 이미 알려진 윈도우 ID를 추적하여
/// appeared / updated 이벤트를 구분하는 데 사용
private class AppStreamWindowTracker: @unchecked Sendable {
    private var knownWindowIDs: Set<UInt64> = []
    private let lock = NSLock()

    func addInitialWindows(_ windows: [WindowInfo]) {
        lock.lock()
        defer { lock.unlock() }
        for w in windows {
            knownWindowIDs.insert(w.windowID)
        }
    }

    /// 윈도우가 새로 나타났으면 true, 이미 있던 윈도우면 false
    func trackAndCheckIfNew(_ windowID: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return knownWindowIDs.insert(windowID).inserted
    }

    func remove(_ windowID: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        knownWindowIDs.remove(windowID)
    }
}

/// AppStream 대상 윈도우가 *처음* 나타났을 때 primary 가상 디스플레이의 좌상단에 고정한다.
///
/// `displayOrigin` 은 primary VD (또는 fallback path 에서 자동 생성된 단일 VD) 의
/// 호스트 글로벌 좌표계 origin 이다. 클라이언트는 이 좌표를 받아서 자기 NSScreen 으로
/// 다시 매핑한다.
///
/// `setWindowFrame` 호출은 그 자체로 `.moved`/`.resized` 이벤트를 다시 유발하므로,
/// 의도한 origin을 `expectedOrigins`에 기록해 두고 동일 origin이 들어오는 self-triggered
/// 이벤트는 무시하여 무한 루프를 방지한다.
private class AppStreamWindowAnchor: @unchecked Sendable {
    private let lock = NSLock()
    private var expectedOrigins: [UInt64: CGPoint] = [:]
    let displayOrigin: CGPoint

    init(displayOrigin: CGPoint) {
        self.displayOrigin = displayOrigin
    }

    /// 윈도우의 좌상단을 primary 가상 디스플레이의 좌상단에 정렬한 frame을 계산하고
    /// expected에 등록한다. 호출측은 반환된 frame으로 `setWindowFrame`을 실행해야 한다.
    func planAnchor(for window: WindowInfo) -> CGRect {
        let bounds = window.bounds
        let newOrigin = displayOrigin
        lock.lock()
        defer { lock.unlock() }
        expectedOrigins[window.windowID] = newOrigin
        return CGRect(
            x: newOrigin.x,
            y: newOrigin.y,
            width: bounds.width,
            height: bounds.height
        )
    }

    /// 들어온 이벤트가 우리 anchor 호출 결과로 발생한 self-triggered 이벤트인지 판정한다.
    /// 일치하면 expected 엔트리를 소비하고 true를 반환한다 (재고정 스킵 지시).
    func consumeIfSelfTriggered(windowId: UInt64, currentBounds: SRRect) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let expected = expectedOrigins[windowId] else { return false }
        if abs(expected.x - currentBounds.x) < 0.5 &&
           abs(expected.y - currentBounds.y) < 0.5 {
            expectedOrigins.removeValue(forKey: windowId)
            return true
        }
        return false
    }

    func remove(windowId: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        expectedOrigins.removeValue(forKey: windowId)
    }
}

extension ProjectionChannel {

    // MARK: - Application List

    func handleApplicationListRequest(_ request: ApplicationListRequest) async throws {
        let appStreamSettings = await NoctilucaServer.shared.settings.appStream

        guard appStreamSettings.enabled else {
            try await self.handle.send(opcode: .applicationListResponse, message: ApplicationListResponse(
                requestId: request.requestId,
                applications: [],
                isLastPage: true
            ))
            return
        }

        let includeIcons = request.flags.contains(.includeIcons)
        let runningOnly = request.flags.contains(.runningOnly)

        let runningApps = await desktopContextManager.runningApplications()
        let runningByBundleId = Dictionary(
            runningApps.compactMap { app -> (String, NSRunningApplication)? in
                guard let id = app.bundleIdentifier else { return nil }
                return (id, app)
            },
            uniquingKeysWith: { first, _ in first }
        )

        let frontmostBundleId = await desktopContextManager.frontmostApplication()?.bundleIdentifier

        var applications: [ApplicationInfo] = []

        for allowedApp in appStreamSettings.allowedApps {
            if let runningApp = runningByBundleId[allowedApp.bundleIdentifier] {
                let state: ApplicationState = (frontmostBundleId == allowedApp.bundleIdentifier) ? .foreground : .background
                let info = await buildApplicationInfo(
                    from: runningApp,
                    state: state,
                    includeIcon: includeIcons,
                    includeWindows: true
                )
                applications.append(info)
            } else if !runningOnly {
                let icon: Data? = includeIcons ? loadIconFromPath(allowedApp.path) : nil
                applications.append(ApplicationInfo(
                    bundleId: allowedApp.bundleIdentifier,
                    displayName: allowedApp.appName,
                    state: .notRunning,
                    windows: [],
                    icon: icon,
                    metadata: [:],
                    hints: 0,
                    flags: 0
                ))
            }
        }

        try await self.handle.send(opcode: .applicationListResponse, message: ApplicationListResponse(
            requestId: request.requestId,
            applications: applications,
            isLastPage: true
        ))
    }

    // MARK: - Application Launch

    func handleApplicationLaunchRequest(_ request: ApplicationLaunchRequest) async throws {
        guard await NoctilucaServer.shared.settings.appStream.enabled else {
            try await self.handle.send(opcode: .applicationLaunchResponse, message: ApplicationLaunchResponse(
                requestId: request.requestId, isSuccess: false, code: 1,
                message: "AppStream is disabled"
            ))
            return
        }

        guard await isAllowedApp(bundleId: request.bundleId) else {
            try await self.handle.send(opcode: .applicationLaunchResponse, message: ApplicationLaunchResponse(
                requestId: request.requestId, isSuccess: false, code: 2,
                message: "Application is not in the allowed list"
            ))
            return
        }

        do {
            _ = try await desktopContextManager.launchApplication(
                bundleId: request.bundleId,
                arguments: request.arguments
            )
            try await self.handle.send(opcode: .applicationLaunchResponse, message: ApplicationLaunchResponse(
                requestId: request.requestId, isSuccess: true, code: 0, message: nil
            ))
        } catch {
            try await self.handle.send(opcode: .applicationLaunchResponse, message: ApplicationLaunchResponse(
                requestId: request.requestId, isSuccess: false, code: 3,
                message: error.localizedDescription
            ))
        }
    }

    // MARK: - Application Terminate

    func handleApplicationTerminateRequest(_ request: ApplicationTerminateRequest) async throws {
        guard await NoctilucaServer.shared.settings.appStream.enabled else {
            try await self.handle.send(opcode: .applicationTerminateResponse, message: ApplicationTerminateResponse(
                requestId: request.requestId, isSuccess: false, code: 1,
                message: "AppStream is disabled"
            ))
            return
        }

        guard await isAllowedApp(bundleId: request.bundleId) else {
            try await self.handle.send(opcode: .applicationTerminateResponse, message: ApplicationTerminateResponse(
                requestId: request.requestId, isSuccess: false, code: 2,
                message: "Application is not in the allowed list"
            ))
            return
        }

        do {
            let result = try await desktopContextManager.terminateApplication(
                bundleId: request.bundleId,
                force: request.force
            )
            try await self.handle.send(opcode: .applicationTerminateResponse, message: ApplicationTerminateResponse(
                requestId: request.requestId, isSuccess: result, code: result ? 0 : 4,
                message: result ? nil : "Terminate request was rejected by the application"
            ))
        } catch {
            try await self.handle.send(opcode: .applicationTerminateResponse, message: ApplicationTerminateResponse(
                requestId: request.requestId, isSuccess: false, code: 3,
                message: error.localizedDescription
            ))
        }
    }

    // MARK: - Subscribe Application Events

    func handleSubscribeApplicationEventsRequest(_ request: SubscribeApplicationEventsRequest) async throws {
        guard await NoctilucaServer.shared.settings.appStream.enabled else {
            return
        }

        let subscriptionId = await desktopContextManager.subscribeAppEvents(
            eventMask: request.eventMask,
            bundleIdFilter: request.bundleIdFilter
        ) { [weak self] event in
            Task { [weak self] in
                try? await self?.sendApplicationChangedEvent(event)
            }
        }

        guard await state.setAppEventSubscription(id: subscriptionId) else {
            await desktopContextManager.unsubscribeAppEvents(id: subscriptionId)
            return
        }

        try await self.handle.send(opcode: .subscribeApplicationEventsResponse, message: SubscribeApplicationEventsResponse(
            requestId: request.requestId,
            subscriptionId: subscriptionId
        ))
    }

    // MARK: - Unsubscribe Application Events

    func handleUnsubscribeApplicationEventsRequest(_ request: UnsubscribeApplicationEventsRequest) async throws {
        guard let subscriptionId = await state.removeAppEventSubscription() else {
            try await self.handle.send(opcode: .unsubscribeApplicationEventsResponse, message: UnsubscribeApplicationEventsResponse(
                requestId: request.requestId,
                subscriptionId: request.subscriptionId,
                isSuccess: false
            ))
            return
        }

        await desktopContextManager.unsubscribeAppEvents(id: subscriptionId)

        try await self.handle.send(opcode: .unsubscribeApplicationEventsResponse, message: UnsubscribeApplicationEventsResponse(
            requestId: request.requestId,
            subscriptionId: subscriptionId,
            isSuccess: true
        ))
    }

    // MARK: - Start AppStream

    func handleStartAppStreamRequest(_ request: StartAppStreamRequest) async throws {
        let appStreamSettings = await NoctilucaServer.shared.settings.appStream

        guard appStreamSettings.enabled else {
            try await self.handle.send(opcode: .startAppStreamResponse, message: StartAppStreamResponse(
                requestId: request.requestId, streamId: UUID(), isSuccess: false, code: 1,
                message: "AppStream is disabled", initialWindows: []
            ))
            return
        }

        guard await isAllowedApp(bundleId: request.bundleId) else {
            try await self.handle.send(opcode: .startAppStreamResponse, message: StartAppStreamResponse(
                requestId: request.requestId, streamId: UUID(), isSuccess: false, code: 2,
                message: "Application is not in the allowed list", initialWindows: []
            ))
            return
        }

        if let existing = await state.currentAppStreamSession() {
            try await self.handle.send(opcode: .startAppStreamResponse, message: StartAppStreamResponse(
                requestId: request.requestId, streamId: UUID(), isSuccess: false, code: 3,
                message: "An AppStream session is already active for \(existing.bundleId)",
                initialWindows: []
            ))
            return
        }

        // 앱이 실행 중인지 확인, 아니면 자동 실행
        var runningApp = await desktopContextManager.findRunningApplication(bundleId: request.bundleId)
        if runningApp == nil {
            do {
                runningApp = try await desktopContextManager.launchApplication(bundleId: request.bundleId)
                try await Task.sleep(for: .milliseconds(500))
            } catch {
                try await self.handle.send(opcode: .startAppStreamResponse, message: StartAppStreamResponse(
                    requestId: request.requestId, streamId: UUID(), isSuccess: false, code: 4,
                    message: "Failed to launch application: \(error.localizedDescription)",
                    initialWindows: []
                ))
                return
            }
        }

        guard let app = runningApp else {
            try await self.handle.send(opcode: .startAppStreamResponse, message: StartAppStreamResponse(
                requestId: request.requestId, streamId: UUID(), isSuccess: false, code: 5,
                message: "Application could not be started", initialWindows: []
            ))
            return
        }

        let streamId = UUID()
        let pid = app.processIdentifier
        let ignoreInvisible = request.flags.contains(.ignoreInvisibleWindows)
        let windowTracker = AppStreamWindowTracker()

        // anchor pool 결정:
        //   - 클라가 사전에 DisplayTransactionRequest 로 만들어둔 purpose=.appStream
        //     VD 들이 있으면 그 중 primary 를 anchor origin 으로 사용 (정상 경로).
        //   - 비어 있으면 단일 3840x2160 VD 를 자동 생성하는 legacy fallback.
        let (fallbackHandle, displayOrigin) = await resolveAppStreamAnchor()
        let windowAnchor = AppStreamWindowAnchor(displayOrigin: displayOrigin)

        // PID 기반 윈도우 이벤트 구독
        let windowSubscriptionId = await desktopContextManager.subscribeWindowEvents(
            eventMask: [.closed, .moved, .resized, .metadataChanged, .focused],
            filter: WindowFilter(expression: WindowFilterExpression(.pid(UInt64(pid)))),
            flags: []
        ) { [weak self, streamId, ignoreInvisible, windowTracker, windowAnchor] windowEvent in
            Task { [weak self] in
                await self?.handleAppStreamWindowEvent(
                    streamId: streamId,
                    windowEvent: windowEvent,
                    ignoreInvisible: ignoreInvisible,
                    windowTracker: windowTracker,
                    windowAnchor: windowAnchor
                )
            }
        }

        // 앱 종료 감지 구독
        let appTerminationSubId = await desktopContextManager.subscribeAppEvents(
            eventMask: .terminated,
            bundleIdFilter: request.bundleId
        ) { [weak self] _ in
            Task { [weak self] in
                await self?.handleAppStreamAppTermination(bundleId: request.bundleId)
            }
        }

        let sessionInfo = ProjectionChannelState.AppStreamSessionInfo(
            streamId: streamId,
            bundleId: request.bundleId,
            pid: pid,
            flags: request.flags,
            windowSubscriptionId: windowSubscriptionId,
            appTerminationSubscriptionId: appTerminationSubId,
            virtualDisplayHandle: fallbackHandle
        )

        guard await state.activateAppStreamSession(sessionInfo) else {
            await desktopContextManager.unsubscribeWindowEvents(id: windowSubscriptionId)
            await desktopContextManager.unsubscribeAppEvents(id: appTerminationSubId)
            if let handle = fallbackHandle {
                let layoutManager = await DisplayLayoutManager.shared
                await layoutManager.destroyVirtualDisplay(handle)
            }
            try await self.handle.send(opcode: .startAppStreamResponse, message: StartAppStreamResponse(
                requestId: request.requestId, streamId: streamId, isSuccess: false, code: 6,
                message: "Failed to activate AppStream session", initialWindows: []
            ))
            return
        }

        let initialWindows = await desktopContextManager.getWindowsForApp(
            pid: pid,
            ignoreInvisible: ignoreInvisible
        )

        windowTracker.addInitialWindows(initialWindows)

        // initialWindows를 즉시 가상 디스플레이 중심으로 이동시킨다.
        await MainActor.run {
            for window in initialWindows {
                self.anchorWindowToCenter(window, using: windowAnchor)
            }
        }

        try await self.handle.send(opcode: .startAppStreamResponse, message: StartAppStreamResponse(
            requestId: request.requestId,
            streamId: streamId,
            isSuccess: true,
            code: 0,
            message: nil,
            initialWindows: initialWindows
        ))
    }

    // MARK: - Stop AppStream

    func handleStopAppStreamRequest(_ request: StopAppStreamRequest) async throws {
        guard let session = await state.removeAppStreamSession(streamId: request.streamId) else {
            try await self.handle.send(opcode: .stopAppStreamResponse, message: StopAppStreamResponse(
                requestId: request.requestId, isSuccess: false
            ))
            return
        }

        await cleanupAppStreamSession(session)

        try await self.handle.send(opcode: .stopAppStreamResponse, message: StopAppStreamResponse(
            requestId: request.requestId, isSuccess: true
        ))
    }

    // MARK: - Push Events

    func sendApplicationChangedEvent(_ event: ApplicationChangedEvent) async throws {
        guard await state.lifecycleState == .active else { return }
        try await self.handle.send(opcode: .applicationChangedEvent, message: event)
    }

    func sendAppStreamWindowEvent(_ event: AppStreamWindowEvent) async throws {
        guard await state.lifecycleState == .active else { return }
        try await self.handle.send(opcode: .appStreamWindowEvent, message: event)
    }

    // MARK: - AppStream Internal

    private func handleAppStreamWindowEvent(
        streamId: UUID,
        windowEvent: WindowChangedEvent,
        ignoreInvisible: Bool,
        windowTracker: AppStreamWindowTracker,
        windowAnchor: AppStreamWindowAnchor
    ) async {
        let eventType: AppStreamWindowEventType
        let info: WindowInfo?
        let isNewlyAppeared: Bool

        if windowEvent.eventType.contains(.closed) {
            eventType = .disappeared
            info = nil
            isNewlyAppeared = false
            windowTracker.remove(windowEvent.windowID)
            windowAnchor.remove(windowId: windowEvent.windowID)
        } else if windowTracker.trackAndCheckIfNew(windowEvent.windowID) {
            eventType = .appeared
            info = windowEvent.info
            isNewlyAppeared = true
        } else {
            eventType = .updated
            info = windowEvent.info
            isNewlyAppeared = false
        }

        // AppStream 윈도우 anchor 정책:
        //  - 새 윈도우(appeared)는 primary 가상 디스플레이의 좌상단 (0,0) 으로 *한 번만* 정렬한다.
        //  - 그 이후 moved/resized 이벤트는 그대로 클라로 push 하고 호스트 윈도우 위치는
        //    호스트/클라 측 입력에 따라 자유롭게 변경되도록 둔다. 클라가 NSWindow 를 드래그하면
        //    WindowManipulationRequest(.setGeometry) 로 호스트 윈도우도 따라간다.
        if let windowInfo = info, isNewlyAppeared {
            await MainActor.run {
                self.anchorWindowToCenter(windowInfo, using: windowAnchor)
            }
        }

        // ignoreInvisibleWindows 플래그 처리
        if ignoreInvisible, let windowInfo = info, windowInfo.flags.contains(.isHidden) {
            return
        }

        do {
            try await sendAppStreamWindowEvent(AppStreamWindowEvent(
                streamId: streamId,
                eventType: eventType,
                windowId: windowEvent.windowID,
                info: info
            ))
        } catch {
            logger.warning("Failed to send AppStreamWindowEvent: \(error)")
        }
    }

    private func handleAppStreamAppTermination(bundleId: String) async {
        guard let session = await state.removeAppStreamSessionForTerminatedApp(bundleId: bundleId) else {
            return
        }

        logger.info("App \(bundleId) terminated during AppStream session \(session.streamId)")
        await cleanupAppStreamSession(session)
    }

    func cleanupAppStreamSession(_ session: ProjectionChannelState.AppStreamSessionInfo) async {
        await desktopContextManager.unsubscribeWindowEvents(id: session.windowSubscriptionId)
        await desktopContextManager.unsubscribeAppEvents(id: session.appTerminationSubscriptionId)
        await MainActor.run {
            AppMenuRegistry.shared.prune(pid: session.pid)
        }

        let layoutManager = await DisplayLayoutManager.shared

        // (1) fallback path 에서 자동 생성된 VD (state.virtualDisplayHandles 에 등록되어 있지 않음)
        if let handle = session.virtualDisplayHandle {
            await layoutManager.destroyVirtualDisplay(handle)
        }

        // (2) 안전망: 클라가 만들었지만 stop 직전에 destroy 트랜잭션을 보내지 못한 잔여분.
        //     클라가 정상 종료한 경우는 이미 takeVirtualDisplay 로 비워져 있어 no-op.
        let leftover = await state.takeVirtualDisplays(withPurpose: .appStream)
        for handle in leftover {
            logger.warning("AppStream cleanup: client did not destroy VD \(handle.displayID); reclaiming")
            await layoutManager.destroyVirtualDisplay(handle)
        }
    }

    // MARK: - Virtual Display & Window Anchoring

    /// Legacy fallback path 의 VD 사양 (3840x2160 @ 60Hz, 1x scale).
    /// 클라이언트가 사전에 VirtualDisplayCreate 트랜잭션을 보내지 않은 경우에만 사용한다.
    private static let appStreamFallbackVirtualDisplaySpec = NOCDisplaySpec(
        resolution: CGSize(width: 3840, height: 2160),
        refreshRate: 60,
        scaleFactor: 1,
        metadata: [:]
    )

    /// AppStream 의 anchor origin (= 새 윈도우가 처음 나타날 때 끌어다 놓는 좌상단) 을 결정한다.
    ///
    /// - 정상 경로: 클라이언트가 미리 만들어둔 `purpose=.appStream` 가상 디스플레이 풀에서
    ///   primary 를 선택하여 그 origin 을 반환한다. 이 path 에서는 fallback handle 이
    ///   없으므로 cleanup 시 추가로 destroy 할 대상도 없다.
    /// - Legacy fallback: 풀이 비어 있으면 단일 3840x2160 VD 를 자동 spawn 한다.
    ///   이렇게 만들어진 핸들은 `AppStreamSessionInfo.virtualDisplayHandle` 에 저장되어
    ///   cleanup 시 destroy 된다.
    private func resolveAppStreamAnchor() async -> (fallbackHandle: NOCVirtualDisplayHandle?, origin: CGPoint) {
        let pool = await state.virtualDisplays(withPurpose: .appStream)

        if !pool.isEmpty {
            let primary = await MainActor.run { selectPrimaryAppStreamDisplay(pool) }
            let bounds = CGDisplayBounds(primary.displayID)
            logger.info("AppStream anchor: using client-provisioned VD #\(primary.displayID) at origin=\(bounds.origin) (\(pool.count) VD in pool)")
            return (nil, bounds.origin)
        }

        return await spawnLegacyFallbackDisplay()
    }

    /// 클라이언트가 VD 를 사전 제공하지 않았을 때 단일 가상 디스플레이를 자동 생성한다.
    /// 이 경로는 구버전 클라 호환성을 위해서만 유지된다.
    private func spawnLegacyFallbackDisplay() async -> (NOCVirtualDisplayHandle?, CGPoint) {
        guard let sessionID = clientSession?.id else {
            logger.warning("AppStream: clientSession 없음. 메인 디스플레이로 fallback.")
            return (nil, mainDisplayOrigin())
        }

        let layoutManager = await DisplayLayoutManager.shared
        do {
            let handle = try await layoutManager.acquireVirtualDisplay(
                ownedBy: sessionID,
                purpose: .appStream,
                specs: [Self.appStreamFallbackVirtualDisplaySpec]
            )

            // 가상 디스플레이는 macOS가 기본적으로 HiDPI(1920x1080@2x) 모드로 잡는 경우가 있어,
            // 명시적으로 3840x2160@1x 모드로 전환한다.
            do {
                try await MainActor.run {
                    try layoutManager.applySpec(
                        to: handle.displayID,
                        spec: Self.appStreamFallbackVirtualDisplaySpec
                    )
                }
            } catch {
                logger.warning("AppStream: failed to apply spec \(Self.appStreamFallbackVirtualDisplaySpec) to display #\(handle.displayID): \(error)")
            }

            let bounds = CGDisplayBounds(handle.displayID)
            logger.warning("AppStream legacy fallback: client did not provision VDs; auto-spawned displayID=\(handle.displayID) bounds=\(bounds)")
            return (handle, bounds.origin)
        } catch {
            logger.warning("AppStream legacy fallback VD spawn failed: \(error). Falling back to main display.")
            return (nil, mainDisplayOrigin())
        }
    }

    /// 클라가 만든 AppStream VD pool 중 anchor 의 기준이 될 primary 를 선택한다.
    ///   1순위: 호스트 OS 의 main display (`CGMainDisplayID`) 가 풀에 있으면 그것
    ///   2순위: 호스트 글로벌 좌표계에서 (0,0) 에 가장 가까운 VD
    ///   3순위: 풀의 첫 번째 항목 (방어적 fallback)
    @MainActor
    private func selectPrimaryAppStreamDisplay(_ pool: [NOCVirtualDisplayHandle]) -> NOCVirtualDisplayHandle {
        let mainID = CGMainDisplayID()
        if let main = pool.first(where: { $0.displayID == mainID }) {
            return main
        }

        let nearest = pool.min { lhs, rhs in
            let lo = CGDisplayBounds(lhs.displayID).origin
            let ro = CGDisplayBounds(rhs.displayID).origin
            let ld = lo.x * lo.x + lo.y * lo.y
            let rd = ro.x * ro.x + ro.y * ro.y
            return ld < rd
        }
        return nearest ?? pool[0]
    }

    private func mainDisplayOrigin() -> CGPoint {
        return CGDisplayBounds(CGMainDisplayID()).origin
    }

    /// MainActor 컨텍스트에서 호출하여 윈도우를 가상 디스플레이 중심으로 이동시킨다.
    @MainActor
    fileprivate func anchorWindowToCenter(
        _ window: WindowInfo,
        using anchor: AppStreamWindowAnchor
    ) {
        let frame = anchor.planAnchor(for: window)
        let windowID = WindowID(window.windowID)
        do {
            try desktopContextManager.setWindowFrame(id: windowID, frame: frame)
        } catch {
            logger.warning("Failed to anchor window \(windowID) to \(frame): \(error)")
        }
    }

    // MARK: - Helpers

    @MainActor
    private func isAllowedApp(bundleId: String) -> Bool {
        let allowedApps = NoctilucaServer.shared.settings.appStream.allowedApps
        return allowedApps.contains { $0.bundleIdentifier == bundleId }
    }

    @MainActor
    private func buildApplicationInfo(
        from app: NSRunningApplication,
        state: ApplicationState,
        includeIcon: Bool,
        includeWindows: Bool
    ) -> ApplicationInfo {
        let windows: [WindowInfo] = if includeWindows {
            desktopContextManager.getWindowsForApp(pid: app.processIdentifier)
        } else {
            []
        }

        let icon: Data? = if includeIcon {
            app.icon?.tiffRepresentation.flatMap {
                NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
            }
        } else {
            nil
        }

        return ApplicationInfo(
            bundleId: app.bundleIdentifier ?? "",
            displayName: app.localizedName ?? "",
            state: state,
            windows: windows,
            icon: icon,
            metadata: [:],
            hints: 0,
            flags: 0
        )
    }

    private func loadIconFromPath(_ path: String) -> Data? {
        let icon = NSWorkspace.shared.icon(forFile: path)
        return icon.tiffRepresentation.flatMap {
            NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
        }
    }
}
