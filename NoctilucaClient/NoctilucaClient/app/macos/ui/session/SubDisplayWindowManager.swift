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

    /// `SubDisplayWindow` 의 `ProjectionSessionSubscription` 은 contentView 의 SwiftUI
    /// wrapper (`SubDisplayWindowProjectionRoot`) 가 `@State` 로 보유한다. wrapper 는 backoff
    /// 재시도 성공 시 subscription 을 새 인스턴스로 교체할 수 있어야 하므로, 이 manager 는
    /// subscription 의 ownership 을 갖지 않는다.
    private(set) var windows: [Int: SubDisplayWindow] = [:]

    init(remoteSession: RemoteSession) {
        self.remoteSession = remoteSession
        super.init()
    }

    func spawn(for displayID: Int) async throws {
        if let existing = windows[displayID] {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        guard let projection = remoteSession.projection else { return }

        let subscription = try await projection.subscribeProjectionSession(for: displayID)
        let window = SubDisplayWindow(
            displayID: displayID,
            remoteSession: remoteSession,
            subscription: subscription,
            onLost: { [weak self] in
                self?.destroy(for: displayID)
            }
        )
        window.delegate = self

        windows[displayID] = window
        window.makeKeyAndOrderFront(nil)
    }

    func destroy(for displayID: Int) {
        // 딕셔너리에서 먼저 제거하여 windowWillClose → destroy 재귀 호출 방지
        guard let window = windows.removeValue(forKey: displayID) else { return }
        // subscription invalidate 는 wrapper 의 onDisappear 가 처리한다.
        window.close()
    }

    func destroyAll() {
        let displayIDs = Array(windows.keys)
        for displayID in displayIDs {
            destroy(for: displayID)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        guard notification.object is SubDisplayWindow else { return }
        remoteSession.hidio?.session.activateSession()
    }

    func windowDidResignKey(_ notification: Notification) {
        guard notification.object is SubDisplayWindow else { return }
        remoteSession.hidio?.session.deactivateSession()
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? SubDisplayWindow else { return }
        destroy(for: window.targetDisplayID)
    }
}

#endif
