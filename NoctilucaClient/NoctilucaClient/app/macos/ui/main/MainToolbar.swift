//
//  MainToolbar.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

#if os(macOS)
import SwiftUI
import AppKit
import Combine

@MainActor
final class MainToolbar: NSObject, NSToolbarDelegate {
    private let viewModel: SessionWindowViewModel
    private let addressBarView: NSHostingView<MainToolbarAddressBar>
    private let minWidth: CGFloat
    private let maxWidth: CGFloat
    private weak var attachedWindow: NSWindow?
    private var focusDismissMonitor: Any?
    private var toolbar: NSToolbar?
    private var phaseCancellable: AnyCancellable?
    private var addressBarHeight: CGFloat {
        max(32, addressBarView.fittingSize.height)
    }
    
    @ViewBuilder
    static func makeAddressBarView(viewModel: SessionWindowViewModel, settingsStore: SettingsStore) -> some View {
    }
    
    init(viewModel: SessionWindowViewModel, settingsStore: SettingsStore, minWidth: CGFloat = 480, maxWidth: CGFloat = 640) {
        let rootView = Self.makeAddressBarView(viewModel: viewModel, settingsStore: settingsStore)
        
        self.viewModel = viewModel
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

        phaseCancellable = viewModel.$phase
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateToolbarItems()
            }
    }

    @MainActor
    deinit {
        if let focusDismissMonitor {
            NSEvent.removeMonitor(focusDismissMonitor)
        }
    }
    
    func attach(to window: NSWindow) {
        addressBarView.frame.size = NSSize(width: maxWidth, height: addressBarHeight)
        
        attachedWindow = window
        installFocusDismissMonitor()
        
        let toolbar = NSToolbar(identifier: "app.noctiluca.client.ui.MainWindow.MainToolbar")
        toolbar.delegate = self
        toolbar.centeredItemIdentifiers = [.nocAddressBar]
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        self.toolbar = toolbar
        
        window.toolbarStyle = .unified
        window.titleVisibility = .hidden
        window.toolbar = toolbar
        window.titlebarAppearsTransparent = true
        
        updateToolbarItems()
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
        switch itemIdentifier {
        case .nocAddressBar:
            let toolbarItem = NSToolbarItem(itemIdentifier: .nocAddressBar)
            toolbarItem.view = addressBarView
            toolbarItem.minSize = NSSize(width: minWidth, height: addressBarHeight)
            toolbarItem.maxSize = NSSize(width: maxWidth, height: addressBarHeight)
            toolbarItem.isBordered = false
            return toolbarItem
        case .nocSettings:
            return makeSymbolItem(
                identifier: .nocSettings,
                systemSymbolName: "gearshape",
                label: "Settings"
            )
        case .nocAddSession:
            return makeSymbolItem(
                identifier: .nocAddSession,
                systemSymbolName: "plus.app",
                label: "New Connection"
            )
        case .nocStopSession:
            return makeSymbolItem(
                identifier: .nocStopSession,
                systemSymbolName: "xmark",
                label: "Stop Session"
            )
        case .nocSwitchDisplay:
            return makeSymbolItem(
                identifier: .nocSwitchDisplay,
                systemSymbolName: "display.2",
                label: "Switch Display"
            )
        case .nocEnableExclusiveInputMode:
            return makeSymbolItem(
                identifier: .nocEnableExclusiveInputMode,
                systemSymbolName: "lock.display",
                label: "Toggle Exclusive Input Mode"
            )
        case .nocAppStream:
            return makeSymbolItem(
                identifier: .nocAppStream,
                systemSymbolName: "app.shadow",
                label: "AppStream"
            )
        default:
            return nil
        }
    }
    
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return defaultItemIdentifiers(for: viewModel.phase)
    }
    
    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [
            .nocAddressBar,
            .nocSettings,
            .nocAddSession,
            .nocStopSession,
            .flexibleSpace,
        ]
    }

    private func defaultItemIdentifiers(for phase: MainWindowPhase) -> [NSToolbarItem.Identifier] {
        switch phase {
        case .newConnection:
            return [
                .flexibleSpace,
                .nocAddressBar,
                .flexibleSpace,
                .nocSettings,
                .nocAddSession
            ]
        case .connecting, .connected:
            return [
                .nocStopSession,
                .flexibleSpace,
                .nocAddressBar,
                .flexibleSpace,
                .nocSwitchDisplay,
                .nocEnableExclusiveInputMode,
                .nocAppStream
            ]
        }
    }

    private func updateToolbarItems() {
        guard let toolbar else {
            return
        }

        let desiredIdentifiers = defaultItemIdentifiers(for: viewModel.phase)
        let currentIdentifiers = toolbar.items.map(\.itemIdentifier)
        if currentIdentifiers == desiredIdentifiers {
            return
        }

        while toolbar.items.count > 0 {
            toolbar.removeItem(at: 0)
        }

        for (index, identifier) in desiredIdentifiers.enumerated() {
            toolbar.insertItem(withItemIdentifier: identifier, at: index)
        }
    }

    private func makeSymbolItem(
        identifier: NSToolbarItem.Identifier,
        systemSymbolName: String,
        label: String
    ) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        // item.label = label
        item.toolTip = label
        item.target = self
        item.action = #selector(handleToolbarAction(_:))
        item.image = NSImage(systemSymbolName: systemSymbolName, accessibilityDescription: label)
        return item
    }

    @objc
    private func handleToolbarAction(_ sender: Any?) {
        guard let item = sender as? NSToolbarItem else {
            return
        }

        switch item.itemIdentifier {
        case .nocSettings:
            if let appDelegate = NSApp.delegate as? AppDelegate {
                appDelegate.showSettingsWindow(nil)
            }
        case .nocStopSession:
            Task { @MainActor in
                await viewModel.stopSession()
            }
        case .nocAddSession:
            viewModel.contactSheetCoordinator.presentContactEditor(for: nil)
        case .nocSwitchDisplay:
            viewModel.shouldPresentDisplaySwitchSheet = true
        case .nocEnableExclusiveInputMode:
            try? viewModel.remoteSession?.hidio?.session.switchMode(to: .exclusive, reason: .userInitiated)
        case .nocAppStream:
            viewModel.appStreamState = .active(bundleIdentifier: "com.apple.Safari")
        default:
            break
        }
    }
}

extension NSToolbarItem.Identifier {
    static let nocAddressBar = NSToolbarItem.Identifier("app.noctiluca.client.ui.MainWindow.MainToolbar.AddressBar")
    static let nocSettings = NSToolbarItem.Identifier("app.noctiluca.client.ui.MainWindow.MainToolbar.Settings")
    static let nocAddSession = NSToolbarItem.Identifier("app.noctiluca.client.ui.MainWindow.MainToolbar.AddSession")
    static let nocStopSession = NSToolbarItem.Identifier("app.noctiluca.client.ui.MainWindow.MainToolbar.StopSession")
    static let nocSwitchDisplay = NSToolbarItem.Identifier("app.noctiluca.client.ui.MainWindow.MainToolbar.SwitchDisplay")
    static let nocEnableExclusiveInputMode = NSToolbarItem.Identifier("app.noctiluca.client.ui.MainWindow.MainToolbar.EnableExclusiveInputMode")
    static let nocAppStream = NSToolbarItem.Identifier("app.noctiluca.client.ui.MainWindow.MainToolbar.AppStream")
}
#endif
