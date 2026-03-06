//
//  SubDisplayWindowManager.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/9/26.
//

#if os(macOS)
import Foundation
import AppKit

@MainActor
class SubDisplayWindowManager: NSObject, NSWindowDelegate {
    let remoteSession: RemoteSession

    struct WindowState {
        let window: SubDisplayWindow
        let subscription: ProjectionSessionSubscription
    }

    private(set) var windows: [Int: WindowState] = [:]

    init(remoteSession: RemoteSession) {
        self.remoteSession = remoteSession
        super.init()
    }

    func spawn(for displayID: Int) async throws {
        if let existing = windows[displayID] {
            existing.window.makeKeyAndOrderFront(nil)
            return
        }

        guard let projection = remoteSession.projection else { return }

        let subscription = try await projection.subscribeProjectionSession(for: displayID)
        let window = SubDisplayWindow(displayID: displayID, remoteSession: remoteSession, subscription: subscription)
        window.delegate = self

        windows[displayID] = WindowState(window: window, subscription: subscription)
        window.makeKeyAndOrderFront(nil)
    }

    func destroy(for displayID: Int) {
        // 딕셔너리에서 먼저 제거하여 windowWillClose → destroy 재귀 호출 방지
        guard let state = windows.removeValue(forKey: displayID) else { return }
        state.subscription.invalidate()
        state.window.close()
    }

    func destroyAll() {
        let displayIDs = Array(windows.keys)
        for displayID in displayIDs {
            destroy(for: displayID)
        }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? SubDisplayWindow else { return }
        destroy(for: window.targetDisplayID)
    }
}

#endif
