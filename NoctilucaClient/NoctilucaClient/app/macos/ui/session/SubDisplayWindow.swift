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
    let mouse: HIDIOAppKitPointer

    weak var hidioController: HIDIOController?

    init(displayID: Int, remoteSession: RemoteSession, subscription: ProjectionSessionSubscription) {
        self.targetDisplayID = displayID
        self.mouse = HIDIOAppKitPointer()
        self.mouse.localIdentifier = "display-\(displayID)"
        self.mouse.scope = .displayId(Int32(targetDisplayID))

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

        self.hidioController = hidio.controller
        hidio.controller.connect(mouse)

        let rootView = RemoteSessionProjectionView(
            remoteSession: remoteSession,
            projection: projection,
            hidio: hidio,
            sourceDescriptor: .constant(.displayID(displayID)),
            subscription: subscription,
            mouse: mouse
        )
            .environmentObject(SettingsStore.shared)

        self.contentView = NSHostingView(rootView: rootView)
    }

    deinit {
        hidioController?.disconnect(mouse.identifierString)
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
