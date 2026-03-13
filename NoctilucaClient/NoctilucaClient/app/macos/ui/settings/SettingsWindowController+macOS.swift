//
//  AppKitSettingsWindowController.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/22/25.
//

#if os(macOS)
import AppKit
import SwiftUI

final class AppKitSettingsWindowController: NSWindowController {
    init(settingsStore: SettingsStore) {
        let contentView = SettingsWindow()
            .environmentObject(settingsStore)
        let hostingView = NSHostingController(rootView: contentView)

        let window = NSWindow(contentViewController: hostingView)
        window.title = "Noctiluca Navigator"
        window.minSize = NSSize(width: 640, height: 480)
        window.collectionBehavior = [.fullScreenNone]
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false

        let toolbar = NSToolbar(identifier: "NoctilucaClient.SettingsToolbar")
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.allowsDisplayModeCustomization = false
        window.toolbar = toolbar
        window.toolbarStyle = .unified

        window.setFrameAutosaveName("NoctilucaClient.SettingsWindow")
        window.center()

        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
