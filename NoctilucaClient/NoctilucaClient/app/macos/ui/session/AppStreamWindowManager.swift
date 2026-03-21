//
//  AppStreamWindowManager.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/9/26.
//

#if os(macOS)
import Foundation
import AppKit
import Combine

import SiriusKitClient

@MainActor
class AppStreamWindowManager: NSObject, NSWindowDelegate {
    let logger = NoctilucaLogger(category: "AppStreamWindowManager")
    let remoteSession: RemoteSession

    struct WindowState {
        let window: AppStreamWindow
        let subscription: ProjectionSessionSubscription
        var windowInfo: WindowInfo
    }

    private(set) var windows: [UInt64: WindowState] = [:]
    private var streamId: UUID?
    private var eventSubscription: AnyCancellable?
    private var resizeDebounceTask: [UInt64: Task<Void, Never>] = [:]

    init(remoteSession: RemoteSession) {
        self.remoteSession = remoteSession
        super.init()
    }

    // MARK: - Lifecycle

    func start(bundleId: String) async throws {
        guard let projectionChannel = remoteSession.projection?.channel else {
            return
        }

        // 이벤트 구독 먼저 시작 (response 전에 도착하는 이벤트 놓치지 않도록)
        subscribeAppStreamEvents()

        let response = try await projectionChannel.startAppStream(
            bundleId: bundleId,
            flags: [.ignoreInvisibleWindows]
        )

        guard response.isSuccess else {
            unsubscribeEvents()
            logger.error("StartAppStream failed: code=\(response.code), message=\(response.message ?? "nil")")
            throw AppStreamError.startFailed(code: response.code, message: response.message)
        }

        self.streamId = response.streamId

        // Z-order: focused 윈도우를 마지막에 생성하여 맨 앞에 오도록 정렬
        let sortedWindows = response.initialWindows.sorted { lhs, rhs in
            let lhsFocused = lhs.flags.contains(.isFocused)
            let rhsFocused = rhs.flags.contains(.isFocused)
            if lhsFocused != rhsFocused { return !lhsFocused }
            return lhs.windowID < rhs.windowID
        }

        for windowInfo in sortedWindows {
            await spawnWindow(windowInfo)
        }
    }

    func stop() async {
        unsubscribeEvents()

        // 모든 윈도우 닫기 (스트림 자체를 종료하므로 서버에 close를 보내지 않음)
        let windowIDs = Array(windows.keys)
        for windowID in windowIDs {
            destroyWindow(windowID: windowID, sendCloseToServer: false)
        }

        if let streamId = self.streamId,
           let projectionChannel = remoteSession.projection?.channel {
            _ = try? await projectionChannel.stopAppStream(streamId: streamId)
        }

        self.streamId = nil
    }

    func destroyAll() {
        unsubscribeEvents()

        let windowIDs = Array(windows.keys)
        for windowID in windowIDs {
            destroyWindow(windowID: windowID, sendCloseToServer: false)
        }

        self.streamId = nil
    }

    // MARK: - Window Management

    private func spawnWindow(_ windowInfo: WindowInfo) async {
        let windowID = windowInfo.windowID

        guard windows[windowID] == nil else {
            windows[windowID]?.window.makeKeyAndOrderFront(nil)
            return
        }

        guard let projection = remoteSession.projection else { return }

        do {
            let subscription = try await projection.subscribeProjectionSession(
                for: .windowID(Int(windowID))
            )

            let window = AppStreamWindow(
                windowID: Int(windowID),
                remoteSession: remoteSession,
                subscription: subscription
            )

            // 서버 bounds에서 크기만 반영 (위치는 클라이언트 자유)
            let serverSize = windowInfo.bounds.cgRect.size
            if serverSize.width > 0 && serverSize.height > 0 {
                window.setContentSize(serverSize)
            }

            window.delegate = self
            window.title = windowInfo.windowTitle

            windows[windowID] = WindowState(
                window: window,
                subscription: subscription,
                windowInfo: windowInfo
            )
            window.makeKeyAndOrderFront(nil)
        } catch {
            logger.warning("Failed to spawn AppStream window \(windowID): \(error)")
        }
    }

    private func destroyWindow(windowID: UInt64, sendCloseToServer: Bool) {
        resizeDebounceTask[windowID]?.cancel()
        resizeDebounceTask.removeValue(forKey: windowID)

        // 딕셔너리에서 먼저 제거하여 windowWillClose → destroyWindow 재귀 호출 방지
        guard let state = windows.removeValue(forKey: windowID) else { return }
        state.subscription.invalidate()
        state.window.close()

        if sendCloseToServer {
            Task { [weak self] in
                guard let projectionChannel = self?.remoteSession.projection?.channel else { return }
                try? await projectionChannel.sendWindowManipulation(
                    windowID: windowID,
                    operation: .stateCommand(.close)
                )
            }
        }
    }

    private func updateWindow(windowID: UInt64, info: WindowInfo) {
        guard windows[windowID] != nil else { return }

        windows[windowID]?.windowInfo = info
        windows[windowID]?.window.title = info.windowTitle

        // 서버에서 크기가 변경되었으면 클라이언트 윈도우 크기도 반영
        let serverSize = info.bounds.cgRect.size
        if serverSize.width > 0 && serverSize.height > 0 {
            let currentSize = windows[windowID]?.window.contentView?.frame.size ?? .zero
            // 리사이즈 무한 루프 방지: 1pt 이하 차이는 무시
            if abs(currentSize.width - serverSize.width) > 1 ||
               abs(currentSize.height - serverSize.height) > 1 {
                windows[windowID]?.window.setContentSize(serverSize)
            }
        }

        // 포커스 처리: isFocused이면 맨 앞으로
        if info.flags.contains(.isFocused) {
            windows[windowID]?.window.orderFront(nil)
        }
    }

    // MARK: - Event Subscription

    private func subscribeAppStreamEvents() {
        guard let projection = remoteSession.projection else { return }

        eventSubscription = projection.channel.events
            .compactMap { event -> AppStreamWindowEvent? in
                if case .appStreamWindowEvent(let e) = event { return e }
                return nil
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                self?.handleAppStreamWindowEvent(event)
            }
    }

    private func unsubscribeEvents() {
        eventSubscription?.cancel()
        eventSubscription = nil
    }

    private func handleAppStreamWindowEvent(_ event: AppStreamWindowEvent) {
        guard event.streamId == self.streamId else { return }

        switch event.eventType {
        case .appeared:
            guard let info = event.info else { return }
            Task { [weak self] in
                await self?.spawnWindow(info)
            }

        case .disappeared:
            destroyWindow(windowID: event.windowId, sendCloseToServer: false)

        case .updated:
            guard let info = event.info else { return }
            updateWindow(windowID: event.windowId, info: info)

        default:
            break
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? AppStreamWindow else { return }

        remoteSession.hidio?.session.activateSession()

        guard let projectionChannel = remoteSession.projection?.channel else { return }
        Task {
            try? await projectionChannel.sendWindowManipulation(
                windowID: UInt64(window.windowID),
                operation: .focus(true)
            )
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object is AppStreamWindow else { return }
        remoteSession.hidio?.session.deactivateSession()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? AppStreamWindow else { return }
        destroyWindow(windowID: UInt64(window.windowID), sendCloseToServer: true)
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        guard let window = notification.object as? AppStreamWindow else { return }
        let windowID = UInt64(window.windowID)
        let contentSize = window.contentView?.frame.size ?? window.frame.size

        resizeDebounceTask[windowID]?.cancel()
        resizeDebounceTask[windowID] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            guard let projectionChannel = self?.remoteSession.projection?.channel else { return }

            let newRect = SRRect(
                x: 0, y: 0,
                width: Double(contentSize.width),
                height: Double(contentSize.height)
            )
            try? await projectionChannel.sendWindowManipulation(
                windowID: windowID,
                operation: .setGeometry(newRect)
            )
        }
    }
}

// MARK: - Error

enum AppStreamError: Error {
    case startFailed(code: UInt32, message: String?)
}

#endif
