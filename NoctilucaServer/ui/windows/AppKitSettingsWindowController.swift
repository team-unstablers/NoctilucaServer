//
//  AppKitSettingsWindowController.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/9/26.
//

import AppKit
import SwiftUI

final class AppKitSettingsWindowController: NSWindowController {
    init() {
        let contentView = SettingsWindow()
            .environmentObject(NoctilucaServer.shared)
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Noctiluca Server 설정"
        window.minSize = NSSize(width: 640, height: 480)
        window.collectionBehavior = [.fullScreenNone]
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.setFrameAutosaveName("NoctilucaServer.SettingsWindow")
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
