//
//  OnboardingWindowController.swift
//  NoctilucaServer
//

import AppKit
import SwiftUI

final class OnboardingWindowController: NSWindowController {
    init() {
        let contentView = OnboardingWindow()
        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.title = String(localized: "onboarding.window.title", defaultValue: "Noctiluca Server")
        window.subtitle = String(localized: "onboarding.window.subtitle", defaultValue: "환영합니다!")
        window.isRestorable = false
        window.collectionBehavior = [.fullScreenNone]
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        window.center()

        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
