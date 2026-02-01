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
        let hostingView = NSHostingView(rootView: contentView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "Settings"
        window.minSize = NSSize(width: 640, height: 480)
        window.collectionBehavior = [.fullScreenNone]
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.setFrameAutosaveName("NoctilucaClient.SettingsWindow")
        window.center()
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
