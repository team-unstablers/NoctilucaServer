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

class SubDisplayWindow: NSWindow {
    let targetDisplayID: Int

    init(displayID: Int, remoteSession: RemoteSession, subscription: ProjectionSessionSubscription) {
        self.targetDisplayID = displayID

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        self.title = Self.displayTitle(for: displayID, remoteSession: remoteSession)
        self.minSize = NSSize(width: 640, height: 480)
        self.isReleasedWhenClosed = false
        self.center()

        guard let projection = remoteSession.projection,
              let hidio = remoteSession.hidio else { return }

        let rootView = RemoteSessionProjectionView(
            remoteSession: remoteSession,
            projection: projection,
            hidio: hidio,
            sourceDescriptor: .constant(.displayID(displayID)),
            subscription: subscription
        )

        self.contentView = NSHostingView(rootView: rootView)
    }

    private static func displayTitle(for displayID: Int, remoteSession: RemoteSession) -> String {
        if let projection = remoteSession.projection,
           let displayInfo = projection.channel.displayLayoutManager.displayLayouts[displayID] {
            let name = displayInfo.displayName
            if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return name
            }
        }
        return "Display #\(displayID)"
    }
}

#endif
