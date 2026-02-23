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
            .environmentObject(SettingsStore.shared)
        let hostingView = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingView)
        window.title = "Noctiluca Server"
        window.minSize = NSSize(width: 640, height: 480)
        window.collectionBehavior = [.fullScreenNone]
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        
        let toolbar = NSToolbar(identifier: "NoctilucaServer.SettingsToolbar")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        toolbar.allowsUserCustomization = false
        
        if #available(macOS 15.0, *) {
            toolbar.allowsDisplayModeCustomization = false
        }

        window.setFrameAutosaveName("NoctilucaServer.SettingsWindow")
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
