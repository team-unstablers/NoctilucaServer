//
//  AppKitSettingsWindowController.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/22/25.
//

#if os(macOS)
import AppKit
import SwiftUI

final class AppKitAboutAppWindowController: NSWindowController {
    init() {
        let contentView = AboutAppView()
        let hostingView = NSHostingView(rootView: contentView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = "About Noctiluca Navigator"
        window.minSize = NSSize(width: 480, height: 600)
        window.collectionBehavior = [.fullScreenNone]
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.setFrameAutosaveName("NoctilucaClient.AboutApp")
        window.center()
        
        super.init(window: window)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
#endif
