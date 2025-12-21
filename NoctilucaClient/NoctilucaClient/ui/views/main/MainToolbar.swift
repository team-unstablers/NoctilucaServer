//
//  MainToolbar.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

#if os(macOS)
import SwiftUI
import AppKit

final class MainToolbar: NSObject, NSToolbarDelegate {
    private let addressBarView: NSHostingView<MainToolbarAddressBar>
    private let minWidth: CGFloat
    private let maxWidth: CGFloat
    private weak var attachedWindow: NSWindow?
    private var focusDismissMonitor: Any?
    private var addressBarHeight: CGFloat {
        max(32, addressBarView.fittingSize.height)
    }
    
    @ViewBuilder
    static func makeAddressBarView(viewModel: MainWindowViewModel, settingsStore: SettingsStore) -> some View {
    }
    
    init(viewModel: MainWindowViewModel, settingsStore: SettingsStore, minWidth: CGFloat = 480, maxWidth: CGFloat = 640) {
        let rootView = Self.makeAddressBarView(viewModel: viewModel, settingsStore: settingsStore)
        
        self.addressBarView = NSHostingView(
            rootView: MainToolbarAddressBar(viewModel: viewModel, settingsStore: settingsStore)
                    // .environmentObject(settingsStore)
        )
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        
        super.init()
        
        addressBarView.translatesAutoresizingMaskIntoConstraints = true
        addressBarView.autoresizingMask = [.width]
        addressBarView.frame = NSRect(x: 0, y: 0, width: maxWidth, height: 32)
    }

    deinit {
        if let focusDismissMonitor {
            NSEvent.removeMonitor(focusDismissMonitor)
        }
    }
    
    func attach(to window: NSWindow) {
        NSWindow.__NOC__swizzleLayoutIfNeeded()

        addressBarView.frame.size = NSSize(width: maxWidth, height: addressBarHeight)
        attachedWindow = window
        installFocusDismissMonitor()
        
        let toolbar = NSToolbar(identifier: "pl.unstabler.NoctilucaClient.ui.MainWindow.MainToolbar")
        toolbar.delegate = self
        toolbar.centeredItemIdentifiers = [.nocAddressBar]
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.toolbar = toolbar
        window.titlebarAppearsTransparent = true
        
        window.centerTrafficLights()
    }

    private func installFocusDismissMonitor() {
        guard focusDismissMonitor == nil else { return }

        focusDismissMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.handleFocusDismissEvent(event) ?? event
        }
    }

    private func handleFocusDismissEvent(_ event: NSEvent) -> NSEvent? {
        guard let window = attachedWindow, event.window === window else {
            return event
        }
        guard let responderView = window.firstResponder as? NSView,
              responderView.isDescendant(of: addressBarView) else {
            return event
        }
        guard let addressBarWindow = addressBarView.window, addressBarWindow === window else {
            return event
        }

        let addressBarFrame = addressBarView.convert(addressBarView.bounds, to: nil)
        let location = event.locationInWindow
        guard !addressBarFrame.contains(location) else {
            return event
        }

        window.makeFirstResponder(nil)
        return event
    }
    
    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == .nocAddressBar else {
            return nil
        }
        
        let toolbarItem = NSToolbarItem(itemIdentifier: .nocAddressBar)
        toolbarItem.view = addressBarView
        toolbarItem.minSize = NSSize(width: minWidth, height: addressBarHeight)
        toolbarItem.maxSize = NSSize(width: maxWidth, height: addressBarHeight)
        toolbarItem.isBordered = false
        
        return toolbarItem
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .nocAddressBar
        ]
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .nocAddressBar
        ]
    }
}

extension NSToolbarItem.Identifier {
    static let nocAddressBar = NSToolbarItem.Identifier("pl.unstabler.NoctilucaClient.ui.MainWindow.MainToolbar.AddressBar")
}
#endif
