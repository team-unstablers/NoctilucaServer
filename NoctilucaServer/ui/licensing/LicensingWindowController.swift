//
//  LicensingWindowController.swift
//  NoctilucaServer
//

import AppKit
import SwiftUI

final class LicensingWindowController: NSWindowController {
    init() {
        let contentView = LicensingWindow()
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = String(localized: "licensing.window.title", defaultValue: "라이선스")
        window.isRestorable = false
        window.collectionBehavior = [.fullScreenNone]
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
