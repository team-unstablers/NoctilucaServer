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

/// AppStream 대상 윈도우를 가상 디스플레이의 좌상단(origin)에 고정한다.
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

    /// 윈도우의 좌상단을 가상 디스플레이의 좌상단에 정렬한 frame을 계산하고 expected에 등록한다.
    /// 호출측은 반환된 frame으로 `setWindowFrame`을 실행해야 한다.
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

        // AppStream 전용 가상 디스플레이 확보 (실패 시 메인 디스플레이로 fallback).
        let (virtualDisplayHandle, displayOrigin) = await acquireAppStreamDisplay()
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
            virtualDisplayHandle: virtualDisplayHandle
        )

        guard await state.activateAppStreamSession(sessionInfo) else {
            await desktopContextManager.unsubscribeWindowEvents(id: windowSubscriptionId)
            await desktopContextManager.unsubscribeAppEvents(id: appTerminationSubId)
            if let handle = virtualDisplayHandle {
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

        // 윈도우 anchor 결정:
        //  - 새 윈도우(appeared)는 무조건 center로 정렬
        //  - moved/resized 이벤트가 들어왔고 self-triggered가 아니면 재고정
        if let windowInfo = info {
            let positionalChange = windowEvent.eventType.contains(.moved)
                || windowEvent.eventType.contains(.resized)
            let shouldAnchor: Bool
            if isNewlyAppeared {
                shouldAnchor = true
            } else if positionalChange {
                shouldAnchor = !windowAnchor.consumeIfSelfTriggered(
                    windowId: windowEvent.windowID,
                    currentBounds: windowInfo.bounds
                )
            } else {
                shouldAnchor = false
            }

            if shouldAnchor {
                await MainActor.run {
                    self.anchorWindowToCenter(windowInfo, using: windowAnchor)
                }
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
        if let handle = session.virtualDisplayHandle {
            let layoutManager = await DisplayLayoutManager.shared
            await layoutManager.destroyVirtualDisplay(handle)
        }
    }

    // MARK: - Virtual Display & Window Anchoring

    /// AppStream용 가상 디스플레이 사양: 3840x2160 @ 60Hz, 1x scale.
    private static let appStreamVirtualDisplaySpec = NOCDisplaySpec(
        resolution: CGSize(width: 3840, height: 2160),
        refreshRate: 60,
        scaleFactor: 1,
        metadata: [:]
    )

    /// AppStream 전용 가상 디스플레이를 생성한다.
    /// 실패 시 핸들 없이 메인 디스플레이의 좌상단 좌표를 반환한다.
    private func acquireAppStreamDisplay() async -> (handle: NOCVirtualDisplayHandle?, origin: CGPoint) {
        guard let sessionID = clientSession?.id else {
            logger.warning("AppStream: clientSession 없음. 메인 디스플레이로 fallback.")
            return (nil, mainDisplayOrigin())
        }

        let layoutManager = await DisplayLayoutManager.shared
        do {
            let handle = try await layoutManager.acquireVirtualDisplay(
                ownedBy: sessionID,
                purpose: .appStream,
                specs: [Self.appStreamVirtualDisplaySpec]
            )
            let bounds = CGDisplayBounds(handle.displayID)
            logger.info("AppStream virtual display acquired: displayID=\(handle.displayID) bounds=\(bounds)")
            return (handle, bounds.origin)
        } catch {
            logger.warning("AppStream virtual display spawn failed: \(error). Falling back to main display.")
            return (nil, mainDisplayOrigin())
        }
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
