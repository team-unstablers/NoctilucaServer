//
//  View+detachedOverlay.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import SwiftUI
import Combine

#if os(macOS)
import AppKit
#endif

enum DetachedOverlayAttachment: Equatable {
    case up
    case down
}

enum DetachedOverlayRole: Equatable {
    case normalWindow(attachTo: DetachedOverlayAttachment)
    case tooltip
    
    var attachment: DetachedOverlayAttachment {
        switch self {
        case .normalWindow(let attachTo):
            return attachTo
        case .tooltip:
            return .down
        }
    }
    
    var isTooltip: Bool {
        if case .tooltip = self {
            return true
        }
        return false
    }
}

extension View {
    func detachedOverlay<Content: View>(
        role: DetachedOverlayRole,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(DetachedOverlayModifier(role: role, overlayContent: content))
    }
}

private enum DetachedOverlayConstants {
    static let normalSpacing: CGFloat = 8
    static let tooltipOffset = CGPoint(x: 12, y: 18)
    static let mouseTrackingInterval: TimeInterval = 1.0 / 30.0
}

#if os(iOS)
struct DetachedOverlayModifier<OverlayContent: View>: ViewModifier {
    let role: DetachedOverlayRole
    let overlayContent: () -> OverlayContent
    
    @State
    private var overlaySize: CGSize = .zero
    
    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { proxy in
                let attachment = role.attachment
                let offsetX = (proxy.size.width - overlaySize.width) / 2
                let offsetY = attachment == .down
                    ? proxy.size.height + DetachedOverlayConstants.normalSpacing
                    : -overlaySize.height - DetachedOverlayConstants.normalSpacing
                
                overlayContent()
                    .onGeometryChange(for: CGSize.self) { proxy in
                        proxy.size
                    } action: { geom in
                        overlaySize = geom
                    }
                    .offset(x: offsetX, y: offsetY)
            }
        }
    }
}
#endif

#if os(macOS)
struct DetachedOverlayModifier<OverlayContent: View>: ViewModifier {
    let role: DetachedOverlayRole
    let overlayContent: () -> OverlayContent
    
    @State
    private var anchorFrame: CGRect = .zero
    
    @StateObject
    private var controller = DetachedOverlayController()
    
    func body(content: Content) -> some View {
        content
            .background(
                DetachedOverlayAnchorView { frame in
                    anchorFrame = frame
                }
            )
            .background(
                DetachedOverlayUpdater(
                    role: role,
                    anchorFrame: anchorFrame,
                    content: overlayAnyView(),
                    controller: controller
                )
            )
            .onDisappear {
                controller.destroy()
            }
    }
    
    private func overlayAnyView() -> AnyView {
        switch role {
        case .normalWindow:
            return AnyView(
                overlayContent()
                    .frame(width: anchorFrame.width)
            )
        case .tooltip:
            return AnyView(overlayContent())
        }
    }
}

private struct DetachedOverlayUpdater: NSViewRepresentable {
    let role: DetachedOverlayRole
    let anchorFrame: CGRect
    let content: AnyView
    let controller: DetachedOverlayController
    
    func makeNSView(context: Context) -> NSView {
        NSView()
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        controller.update(role: role, anchorFrame: anchorFrame, content: content)
    }
}

private struct DetachedOverlayAnchorView: NSViewRepresentable {
    let onFrameChange: (CGRect) -> Void
    
    func makeNSView(context: Context) -> AnchorNSView {
        let view = AnchorNSView()
        view.onFrameChange = onFrameChange
        return view
    }
    
    func updateNSView(_ nsView: AnchorNSView, context: Context) {
        nsView.onFrameChange = onFrameChange
        nsView.reportFrame()
    }
    
    final class AnchorNSView: NSView {
        var onFrameChange: ((CGRect) -> Void)?
        private var windowObservers: [NSObjectProtocol] = []
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachWindowObservers()
            reportFrame()
        }
        
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if window !== newWindow {
                detachWindowObservers()
            }
            super.viewWillMove(toWindow: newWindow)
        }
        
        override func layout() {
            super.layout()
            reportFrame()
        }
        
        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            reportFrame()
        }
        
        deinit {
            detachWindowObservers()
        }
        
        func reportFrame() {
            guard let window else { return }
            let frameInWindow = convert(bounds, to: nil)
            let frameInScreen = window.convertToScreen(frameInWindow)
            onFrameChange?(frameInScreen)
        }
        
        private func attachWindowObservers() {
            detachWindowObservers()
            guard let window else { return }
            
            let center = NotificationCenter.default
            windowObservers.append(
                center.addObserver(
                    forName: NSWindow.didMoveNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.reportFrame()
                }
            )
            windowObservers.append(
                center.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.reportFrame()
                }
            )
        }
        
        private func detachWindowObservers() {
            guard !windowObservers.isEmpty else { return }
            let center = NotificationCenter.default
            windowObservers.forEach { center.removeObserver($0) }
            windowObservers.removeAll()
        }
    }
}

private final class DetachedOverlayController: ObservableObject {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var role: DetachedOverlayRole = .normalWindow(attachTo: .down)
    private var anchorFrame: CGRect = .zero
    private var contentSize: CGSize = .zero
    private var mouseLocation: NSPoint = .zero
    private var mouseTimer: Timer?
    
    func update(role: DetachedOverlayRole, anchorFrame: CGRect, content: AnyView) {
        self.role = role
        self.anchorFrame = anchorFrame
        
        ensurePanel()
        hostingView?.rootView = content
        
        applyRoleConfiguration()
        updateContentSize()
        updateWindowFrame()
    }
    
    func destroy() {
        stopMouseTracking()
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        hostingView = nil
    }
    
    private func ensurePanel() {
        guard panel == nil else { return }
        
        let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isReleasedWhenClosed = false
        panel.contentView = hostingView
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        panel.level = .floating
        
        self.panel = panel
        self.hostingView = hostingView
    }
    
    private func applyRoleConfiguration() {
        guard let panel else { return }
        
        panel.ignoresMouseEvents = role.isTooltip
        panel.acceptsMouseMovedEvents = !role.isTooltip
        panel.level = role.isTooltip ? .statusBar : .floating
        
        if role.isTooltip {
            startMouseTracking()
        } else {
            stopMouseTracking()
        }
    }
    
    private func updateContentSize() {
        guard let panel, let hostingView else { return }
        
        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let width = max(fitting.width, 0)
        let height = max(fitting.height, 0)
        let size = CGSize(width: width, height: height)
        
        contentSize = size
        
        guard size.width > 1, size.height > 1 else {
            panel.orderOut(nil)
            return
        }
        
        hostingView.setFrameSize(size)
        panel.setContentSize(size)
    }
    
    private func updateWindowFrame() {
        guard let panel else { return }
        guard contentSize.width > 1, contentSize.height > 1 else { return }
        
        let origin: CGPoint
        
        switch role {
        case .tooltip:
            let location = mouseLocation
            origin = CGPoint(
                x: location.x + DetachedOverlayConstants.tooltipOffset.x,
                y: location.y - DetachedOverlayConstants.tooltipOffset.y - contentSize.height
            )
        case .normalWindow(let attachTo):
            guard anchorFrame.width > 1, anchorFrame.height > 1 else {
                panel.orderOut(nil)
                return
            }
            
            let x = anchorFrame.midX - contentSize.width / 2
            let y = attachTo == .down
                ? anchorFrame.minY - DetachedOverlayConstants.normalSpacing - contentSize.height
                : anchorFrame.maxY + DetachedOverlayConstants.normalSpacing
            origin = CGPoint(x: x, y: y)
        }
        
        panel.setFrame(NSRect(origin: origin, size: contentSize), display: false)
        if !panel.isVisible {
            panel.orderFront(nil)
        }
    }
    
    private func startMouseTracking() {
        guard mouseTimer == nil else { return }
        
        mouseLocation = NSEvent.mouseLocation
        mouseTimer = Timer.scheduledTimer(withTimeInterval: DetachedOverlayConstants.mouseTrackingInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            mouseLocation = NSEvent.mouseLocation
            updateWindowFrame()
        }
        if let mouseTimer {
            RunLoop.main.add(mouseTimer, forMode: .common)
        }
    }
    
    private func stopMouseTracking() {
        mouseTimer?.invalidate()
        mouseTimer = nil
    }
}
#endif
