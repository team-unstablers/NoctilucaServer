//
//  AboutAppWindowController.swift
//  NoctilucaServer
//

import AppKit
import SwiftUI

final class AboutAppWindowController: NSWindowController {
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
        window.title = String(localized: "about.window.title", defaultValue: "Noctiluca Server에 대하여")
        window.minSize = NSSize(width: 480, height: 600)
        window.collectionBehavior = [.fullScreenNone]
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.setFrameAutosaveName("NoctilucaServer.AboutApp")
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
