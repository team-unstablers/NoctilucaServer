//
//  SubDisplayWindow.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/9/26.
//

#if os(macOS)

import Foundation
import AppKit
import SwiftUI

import SiriusKitClient

class AppStreamWindow: NSWindow {
    let windowID: Int
    let mouse: HIDIOAppKitPointer

    init(windowID: Int, remoteSession: RemoteSession, subscription: ProjectionSessionSubscription) {
        self.windowID = windowID
        self.mouse = HIDIOAppKitPointer()
        self.mouse.scope = .windowId(Int64(windowID))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        self.title = Self.displayTitle(for: windowID, remoteSession: remoteSession)
        self.minSize = NSSize(width: 640, height: 480)
        self.isReleasedWhenClosed = false
        self.center()

        guard let projection = remoteSession.projection,
              let hidio = remoteSession.hidio else { return }

        let rootView = RemoteSessionProjectionView(
            remoteSession: remoteSession,
            projection: projection,
            hidio: hidio,
            sourceDescriptor: .constant(.windowID(windowID)),
            subscription: subscription,
            mouse: mouse
        )
            .environmentObject(SettingsStore.shared)

        self.contentView = NSHostingView(rootView: rootView)
    }

    private static func displayTitle(for windowID: Int, remoteSession: RemoteSession) -> String {
        return "AppStream Window (streaming #\(windowID))"
    }
}

#endif
