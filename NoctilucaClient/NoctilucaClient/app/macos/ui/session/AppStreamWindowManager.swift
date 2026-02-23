//
//  SubDisplayWindowManager.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/9/26.
//

#if os(macOS)
import Foundation
import AppKit

import SiriusKit

@MainActor
class AppStreamWindowManager: NSObject, NSWindowDelegate {
    let remoteSession: RemoteSession

    struct WindowState {
        let window: AppStreamWindow
        let subscription: ProjectionSessionSubscription
    }

    private(set) var windows: [Int: WindowState] = [:]

    init(remoteSession: RemoteSession) {
        self.remoteSession = remoteSession
        super.init()
    }
    
    func start() async throws {
        guard let projectionChannel = self.remoteSession.projection?.channel else {
            return
        }
        
        // TODO: filter
        let response = try await projectionChannel.requestWindowList()
        
        let windows = response.windows.filter { $0.applicationBundleID == "com.apple.dt.Xcode" }
        
        for window in windows {
            try? await self.spawn(window)
        }
    }

    func spawn(_ windowInfo: WindowInfo) async throws {
        let windowID = Int(windowInfo.windowID)
        if let existing = windows[windowID] {
            existing.window.makeKeyAndOrderFront(nil)
            return
        }

        guard let projection = remoteSession.projection else { return }

        let subscription = try await projection.subscribeProjectionSession(for: .windowID(windowID))
        let window = AppStreamWindow(windowID: windowID, remoteSession: remoteSession, subscription: subscription)
        window.setContentSize(windowInfo.bounds.cgRect.size)
        window.delegate = self

        windows[windowID] = WindowState(window: window, subscription: subscription)
        window.makeKeyAndOrderFront(nil)
    }

    func destroy(for displayID: Int) {
        // 딕셔너리에서 먼저 제거하여 windowWillClose → destroy 재귀 호출 방지
        guard let state = windows.removeValue(forKey: displayID) else { return }
        state.window.close()
        // state가 스코프를 벗어나면서 ticket deinit → 세션 참조 해제
    }

    func destroyAll() {
        let displayIDs = Array(windows.keys)
        for displayID in displayIDs {
            destroy(for: displayID)
        }
    }

    // MARK: - NSWindowDelegate
    
    func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? AppStreamWindow else { return }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? AppStreamWindow else { return }
        destroy(for: window.windowID)
    }
}

#endif
