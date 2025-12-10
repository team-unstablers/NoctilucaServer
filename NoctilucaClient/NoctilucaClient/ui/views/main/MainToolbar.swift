//
//  MainToolbar.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import Foundation

import SwiftUI
import AppKit

struct MainToolbar: NSViewRepresentable {
    let addressBar: NSHostingView<AnyView>
    
    class DummyView: NSView {
        let windowAttachedHandler: (NSWindow) -> Void
        
        init(windowAttachedHandler: @escaping (NSWindow) -> Void) {
            self.windowAttachedHandler = windowAttachedHandler
            super.init(frame: .zero)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            
            guard let window = self.window else {
                return
            }
            
            windowAttachedHandler(window)
        }
    }
    
    class Coordinator: NSObject, NSToolbarDelegate {
        let addressBar: NSHostingView<AnyView>
        var nsWindow: NSWindow? = nil
        private lazy var addressBarContainer = ToolbarConstrainedHost(
            content: addressBar,
            minWidth: 480,
            maxWidth: 640
        )
        
        init(addressBar: NSHostingView<AnyView>) {
            self.addressBar = addressBar
            
            super.init()
        }
        
        func setupToolbar() {
            guard let window = nsWindow else { return }
            
            NSWindow.__NOC__swizzleLayoutIfNeeded()
            

            let toolbar = NSToolbar(identifier: "pl.unstabler.NoctilucaClient.ui.MainWindow.MainToolbar")
            toolbar.delegate = self
            toolbar.centeredItemIdentifiers = [.nocAddressBar]
            
            /*
            toolbar.showsBaselineSeparator = false
            window.titlebarAppearsTransparent = true
             */

            window.toolbarStyle = .unified
            window.titleVisibility = .hidden
            window.toolbar = toolbar
            
            window.titlebarAppearsTransparent = true
            
            // FIXME
            /*
            let visualEffect = NSVisualEffectView()
            
            visualEffect.blendingMode = .behindWindow
            visualEffect.state = .active
            visualEffect.material = .mediumLight
             
             window.contentView = visualEffect
             */
        }
        
        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
            if itemIdentifier == .nocAddressBar {
                let toolbarItem = NSToolbarItem(itemIdentifier: .nocAddressBar)
                toolbarItem.target = self
                toolbarItem.view = addressBarContainer
                toolbarItem.style = .plain
                toolbarItem.isBordered = false

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
        let view = DummyView { window in
            context.coordinator.nsWindow = window
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

private final class ToolbarConstrainedHost: NSView {
    private let content: NSView
    private let minWidth: CGFloat
    private let maxWidth: CGFloat
    
    init(content: NSView, minWidth: CGFloat, maxWidth: CGFloat) {
        self.content = content
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        super.init(frame: .zero)
        
        // DEBUG: set background to blue
        /*
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.blue.cgColor
         */
        
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        
        content.translatesAutoresizingMaskIntoConstraints = false
        content.setContentHuggingPriority(.defaultLow, for: .horizontal)
        content.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(content)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var intrinsicContentSize: NSSize {
        return NSSize(width: NSView.noIntrinsicMetric, height: content.intrinsicContentSize.height)
    }
    
    override func viewDidMoveToSuperview() {
        guard let superview = self.superview else {
            return
        }
        
        // reset constraints
        NSLayoutConstraint.deactivate(self.constraints)

        let constraints = [
            widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth),
            widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth),
            content.leadingAnchor.constraint(equalTo: superview.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: superview.trailingAnchor),
            content.topAnchor.constraint(equalTo: superview.topAnchor),
            content.bottomAnchor.constraint(equalTo: superview.bottomAnchor),
            content.widthAnchor.constraint(greaterThanOrEqualToConstant: minWidth + 8),
            content.widthAnchor.constraint(lessThanOrEqualToConstant: maxWidth + 8)
        ]
                
        NSLayoutConstraint.activate(constraints)
    }
    
}

@objc
extension NSWindow {
    static var __NOC__swizzled_layoutIfNeeded: Bool = false
    static var __NOC__original_layoutIfNeeded: Method? = nil
    
    @objc
    static func __NOC__swizzleLayoutIfNeeded() {
        guard !__NOC__swizzled_layoutIfNeeded else {
            return
        }
        
        __NOC__swizzled_layoutIfNeeded = true

        let originalSelector = #selector(layoutIfNeeded)
        let swizzledSelector = #selector(__NOC__layoutIfNeeded)
        
        guard let originalMethod = class_getInstanceMethod(NSWindow.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(NSWindow.self, swizzledSelector) else {
            return
        }
        
        __NOC__original_layoutIfNeeded = originalMethod
        
        method_exchangeImplementations(originalMethod, swizzledMethod)
        
    }
    
    @objc
    func __NOC__layoutIfNeeded() {
        // call original method
        self.__NOC__layoutIfNeeded()
        
        // FIXME: self.class = ...
        if self.toolbar != nil {
            toolbarStyle = .unified
            titleVisibility = .hidden
        }

        self.centerTrafficLights()
    }
    
    @objc
    func centerTrafficLights() {
        guard self.toolbar != nil else {
            // 툴바가 없으면 신호등 버튼을 굳이 정렬할 필요가 없으므로 종료
            return
        }
        // 신호등 버튼 3개 가져오기
        let trafficLightButtons: [NSButton?] = [
            standardWindowButton(.closeButton),
            standardWindowButton(.miniaturizeButton),
            standardWindowButton(.zoomButton)
        ]
        
        // 버튼들의 부모 뷰(Titlebar Container)가 존재해야 계산 가능
        guard let titlebarContainer = trafficLightButtons.first??.superview else { return }
        
        for button in trafficLightButtons {
            guard let btn = button else { continue }
            
            // 핵심 계산: (부모 뷰 높이 - 버튼 높이) / 2
            // 이렇게 하면 수직 중앙에 위치하게 됩니다.
            let centeredY = (titlebarContainer.bounds.height - btn.frame.height) / 2
            
            // 위치 적용
            // 주의: Auto Layout 간섭을 피하기 위해 frame을 직접 수정합니다.
            btn.frame.origin.y = centeredY
        }
    }
}
