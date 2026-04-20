//
//  ProjectionChannel+appman.swift
//  NoctilucaServer
//

import Foundation
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

        // PID 기반 윈도우 이벤트 구독
        let windowSubscriptionId = await desktopContextManager.subscribeWindowEvents(
            eventMask: [.closed, .moved, .resized, .metadataChanged, .focused],
            filter: WindowFilter(expression: WindowFilterExpression(.pid(UInt64(pid)))),
            flags: []
        ) { [weak self, streamId, ignoreInvisible, windowTracker] windowEvent in
            print(windowEvent)
            Task { [weak self] in
                await self?.handleAppStreamWindowEvent(
                    streamId: streamId,
                    windowEvent: windowEvent,
                    ignoreInvisible: ignoreInvisible,
                    windowTracker: windowTracker
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
            appTerminationSubscriptionId: appTerminationSubId
        )

        guard await state.activateAppStreamSession(sessionInfo) else {
            await desktopContextManager.unsubscribeWindowEvents(id: windowSubscriptionId)
            await desktopContextManager.unsubscribeAppEvents(id: appTerminationSubId)
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
        print(initialWindows)
        
        windowTracker.addInitialWindows(initialWindows)

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
        windowTracker: AppStreamWindowTracker
    ) async {
        let eventType: AppStreamWindowEventType
        let info: WindowInfo?

        if windowEvent.eventType.contains(.closed) {
            eventType = .disappeared
            info = nil
            windowTracker.remove(windowEvent.windowID)
        } else if windowTracker.trackAndCheckIfNew(windowEvent.windowID) {
            eventType = .appeared
            info = windowEvent.info
        } else {
            eventType = .updated
            info = windowEvent.info
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
