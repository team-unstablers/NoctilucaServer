//
//  AppKitDebugWindowController.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 4/3/26.
//

#if os(macOS)
import Foundation
import AppKit
import SwiftUI

@MainActor
final class AppKitDebugWindowController {
    private var window: NSWindow?
    private var viewModel: RemoteSessionDebugViewModel?

    /// 디버그 윈도우를 세션 창의 child로 생성하여 표시합니다.
    func show(for remoteSession: RemoteSession, parentWindow: NSWindow) {
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            return
        }

        let vm = RemoteSessionDebugViewModel(remoteSession: remoteSession)
        self.viewModel = vm

        let contentView = RemoteSessionDebugView(viewModel: vm)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.sizingOptions = [.minSize]

        let debugWindow = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 600),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        debugWindow.contentView = hostingView
        debugWindow.title = "Session Debug"
        debugWindow.minSize = NSSize(width: 360, height: 400)
        debugWindow.isReleasedWhenClosed = false

        // 부모 창 우측에 위치
        if let parentFrame = parentWindow.screen?.visibleFrame {
            let parentRight = parentWindow.frame.maxX
            let x = min(parentRight + 12, parentFrame.maxX - 480)
            let y = parentWindow.frame.midY - 300
            debugWindow.setFrameOrigin(NSPoint(x: x, y: y))
        }

        parentWindow.addChildWindow(debugWindow, ordered: .above)
        debugWindow.makeKeyAndOrderFront(nil)

        self.window = debugWindow
    }

    /// 디버그 윈도우를 닫습니다.
    func close() {
        if let window {
            window.parent?.removeChildWindow(window)
            window.close()
        }
        self.window = nil
        self.viewModel = nil
    }

    var isVisible: Bool {
        window != nil
    }
}
#endif
