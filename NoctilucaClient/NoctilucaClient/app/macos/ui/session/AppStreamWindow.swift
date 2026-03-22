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
import Combine

import SiriusKitClient

@MainActor
class ObservableWindowInfo: ObservableObject {
    @Published var windowInfo: WindowInfo

    init(_ windowInfo: WindowInfo) {
        self.windowInfo = windowInfo
    }
}

class AppStreamWindow: NSWindow {
    let windowID: Int
    let mouse: HIDIOAppKitPointer
    let windowInfoStore: ObservableWindowInfo

    weak var hidioController: HIDIOController?

    init(windowID: Int, remoteSession: RemoteSession, subscription: ProjectionSessionSubscription, windowInfoStore: ObservableWindowInfo) {
        self.windowID = windowID
        self.windowInfoStore = windowInfoStore
        self.mouse = HIDIOAppKitPointer()
        self.mouse.localIdentifier = "window-\(windowID)"
        self.mouse.scope = .windowId(Int64(windowID))

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        self.title = Self.displayTitle(for: windowID, remoteSession: remoteSession)
        
        self.styleMask.insert(.fullSizeContentView)
        self.titlebarAppearsTransparent = true
        self.titleVisibility = .hidden
        
        self.minSize = NSSize(width: 640, height: 480)
        self.isReleasedWhenClosed = false
        self.center()

        guard let projection = remoteSession.projection,
              let hidio = remoteSession.hidio else { return }
        
        self.hidioController = hidio.controller
        hidio.controller.connect(mouse)

        let rootView = ZStack(alignment: .topTrailing) {
            RemoteSessionProjectionView(
                remoteSession: remoteSession,
                projection: projection,
                hidio: hidio,
                sourceDescriptor: .constant(.windowID(windowID)),
                subscription: subscription,
                mouse: mouse
            )

            WindowInfoOverlay(store: windowInfoStore)
                .padding(8)
        }
        .ignoresSafeArea(.all)
        .environmentObject(SettingsStore.shared)

        self.contentView = NSHostingView(rootView: rootView)
    }
    
    override func sendEvent(_ event: NSEvent) {
        if !isKeyWindow {
            switch event.type {
            case .mouseMoved, .mouseEntered:
                makeKeyAndOrderFront(nil)
            default:
                break
            }
        }
        super.sendEvent(event)
    }

    deinit {
        hidioController?.disconnect(mouse.identifierString)
    }

    private static func displayTitle(for windowID: Int, remoteSession: RemoteSession) -> String {
        return "AppStream Window (streaming #\(windowID))"
    }
}

#endif
