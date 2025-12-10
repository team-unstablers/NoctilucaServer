//
//  MainToolbar.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import SwiftUI
import AppKit

struct MainToolbar: NSViewRepresentable {
    let addressBar: NSHostingView<AnyView>
    
    class Coordinator: NSObject, NSToolbarDelegate {
        let addressBar: NSHostingView<AnyView>
        var nsWindow: NSWindow? = nil
        
        init(addressBar: NSHostingView<AnyView>) {
            self.addressBar = addressBar
            
            super.init()
        }
        
        func setupToolbar() {
            guard let window = nsWindow else { return }
            
            window.toolbarStyle = .unified

            let toolbar = NSToolbar(identifier: "pl.unstabler.NoctilucaClient.ui.MainWindow.MainToolbar")
            toolbar.delegate = self
            
            window.titleVisibility = .hidden
            window.toolbar = toolbar
        }
        
        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
            if itemIdentifier == .nocAddressBar {
                let toolbarItem = NSToolbarItem(itemIdentifier: .nocAddressBar)
                toolbarItem.target = self
                toolbarItem.view = addressBar
                
                // TODO: set min/max width constraint (min = 480, max = 640)
                

                return toolbarItem
            }
            
            return nil
        }
        
        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            return [
                .flexibleSpace,
                .nocAddressBar,
                .flexibleSpace,
            ]
        }
        
        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            return [
                .nocAddressBar,
                .space,
                .flexibleSpace
            ]
        }
        
        func toolbarWillAddItem(_ notification: Notification) {
            
        }
        
        func toolbarDidRemoveItem(_ notification: Notification) {
            
        }
        
        func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            return []
        }
    }
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.nsWindow = view.window!
            context.coordinator.setupToolbar()
        }
        
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(addressBar: self.addressBar)
    }
}

extension NSToolbarItem.Identifier {
    static let nocAddressBar = NSToolbarItem.Identifier("pl.unstabler.NoctilucaClient.ui.MainWindow.MainToolbar.AddressBar")
}
