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
    
    func attach(to window: NSWindow) {
        NSWindow.__NOC__swizzleLayoutIfNeeded()

        addressBarView.frame.size = NSSize(width: maxWidth, height: addressBarHeight)
        
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
