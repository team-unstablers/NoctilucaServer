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

#if os(iOS) || os(tvOS)
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
                    .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 4)
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
    private var anchorState: DetachedOverlayAnchorState = .hidden
    
    @StateObject
    private var controller = DetachedOverlayController()
    
    func body(content: Content) -> some View {
        content
            .background(
                DetachedOverlayAnchorView { state in
                    // HACK: prevent 'Modifying state during view update, this will cause undefined behavior.'
                    DispatchQueue.main.async {
                        self.updateAnchorState(state)
                    }
                }
            )
            .background(
                DetachedOverlayUpdater(
                    role: role,
                    anchorState: anchorState,
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
                    .frame(width: anchorState.frame.width)
            )
        case .tooltip:
            return AnyView(overlayContent())
        }
    }
    
    private func updateAnchorState(_ state: DetachedOverlayAnchorState) {
        anchorState = state
    }
}

private struct DetachedOverlayUpdater: NSViewRepresentable {
    let role: DetachedOverlayRole
    let anchorState: DetachedOverlayAnchorState
    let content: AnyView
    let controller: DetachedOverlayController
    
    func makeNSView(context: Context) -> NSView {
        NSView()
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        controller.update(role: role, anchorState: anchorState, content: content)
    }
}

private struct DetachedOverlayAnchorState: Equatable {
    var frame: CGRect
    var isKey: Bool
    var isMiniaturized: Bool
    var isVisible: Bool
    var isAppActive: Bool
    
    static let hidden = DetachedOverlayAnchorState(
        frame: .zero,
        isKey: false,
        isMiniaturized: false,
        isVisible: false,
        isAppActive: false
    )
    
    var shouldDisplayOverlay: Bool {
        guard isAppActive else { return false }
        guard isKey else { return false }
        guard !isMiniaturized else { return false }
        return isVisible
    }
}

private struct DetachedOverlayAnchorView: NSViewRepresentable {
    let onStateChange: (DetachedOverlayAnchorState) -> Void
    
    func makeNSView(context: Context) -> AnchorNSView {
        let view = AnchorNSView()
        view.onStateChange = onStateChange
        return view
    }
    
    func updateNSView(_ nsView: AnchorNSView, context: Context) {
        nsView.onStateChange = onStateChange
        nsView.reportFrame()
    }
    
    final class AnchorNSView: NSView {
        var onStateChange: ((DetachedOverlayAnchorState) -> Void)?
        private var windowObservers: [NSObjectProtocol] = []
        private var appObservers: [NSObjectProtocol] = []
        
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachWindowObservers()
            attachAppObservers()
            reportFrame()
        }
        
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if window !== newWindow {
                detachWindowObservers()
                detachAppObservers()
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
            detachAppObservers()
        }
        
        func reportFrame() {
            guard let window else {
                onStateChange?(.hidden)
                return
            }
            
            let frameInWindow = convert(bounds, to: nil)
            let frameInScreen = window.convertToScreen(frameInWindow)
            let isVisible = window.isVisible && window.occlusionState.contains(.visible)
            let state = DetachedOverlayAnchorState(
                frame: frameInScreen,
                isKey: window.isKeyWindow,
                isMiniaturized: window.isMiniaturized,
                isVisible: isVisible,
                isAppActive: NSApp.isActive
            )
            onStateChange?(state)
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
            windowObservers.append(
                center.addObserver(
                    forName: NSWindow.didBecomeKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.reportFrame()
                }
            )
            windowObservers.append(
                center.addObserver(
                    forName: NSWindow.didResignKeyNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.reportFrame()
                }
            )
            windowObservers.append(
                center.addObserver(
                    forName: NSWindow.didMiniaturizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.reportFrame()
                }
            )
            windowObservers.append(
                center.addObserver(
                    forName: NSWindow.didDeminiaturizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self] _ in
                    self?.reportFrame()
                }
            )
            windowObservers.append(
                center.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification,
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
        
        private func attachAppObservers() {
            detachAppObservers()
            let center = NotificationCenter.default
            appObservers.append(
                center.addObserver(
                    forName: NSApplication.didBecomeActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.reportFrame()
                }
            )
            appObservers.append(
                center.addObserver(
                    forName: NSApplication.didResignActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    self?.reportFrame()
                }
            )
        }
        
        private func detachAppObservers() {
            guard !appObservers.isEmpty else { return }
            let center = NotificationCenter.default
            appObservers.forEach { center.removeObserver($0) }
            appObservers.removeAll()
        }
    }
}

private final class DetachedOverlayController: ObservableObject {
    private var panel: NSPanel?
    private var hostingView: NSHostingView<AnyView>?
    private var role: DetachedOverlayRole = .normalWindow(attachTo: .down)
    private var anchorState: DetachedOverlayAnchorState = .hidden
    private var contentSize: CGSize = .zero
    private var mouseLocation: NSPoint = .zero
    private var mouseTimer: Timer?
    
    func update(role: DetachedOverlayRole, anchorState: DetachedOverlayAnchorState, content: AnyView) {
        self.role = role
        self.anchorState = anchorState
        
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
        panel.hasShadow = true
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
        
        if role.isTooltip, anchorState.shouldDisplayOverlay {
            mouseLocation = NSEvent.mouseLocation
            updateWindowFrame()
            // startMouseTracking()
        } else {
            updateWindowFrame()
            // stopMouseTracking()
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
        guard anchorState.shouldDisplayOverlay else {
            panel.orderOut(nil)
            return
        }
        
        let origin: CGPoint
        
        switch role {
        case .tooltip:
            let location = mouseLocation
            origin = CGPoint(
                x: location.x + DetachedOverlayConstants.tooltipOffset.x,
                y: location.y - DetachedOverlayConstants.tooltipOffset.y - contentSize.height
            )
        case .normalWindow(let attachTo):
            let anchorFrame = anchorState.frame
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
        /*
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
         */
    }
    
    private func stopMouseTracking() {
        /*
        mouseTimer?.invalidate()
        mouseTimer = nil
         */
    }
}
#endif
