//
//  View+detachedSheet.swift
//  NoctilucaClient
//

import SwiftUI
import Combine

#if os(macOS)
import AppKit
#endif

extension View {
    func detachedSheet<Content: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
#if os(macOS)
        modifier(DetachedSheetModifier(isPresented: isPresented, sheetContent: content))
#else
        self.sheet(isPresented: isPresented, content: content)
#endif
    }
}

#if os(macOS)
private struct DetachedSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    let sheetContent: () -> SheetContent

    @StateObject
    private var controller = DetachedSheetController()

    func body(content: Content) -> some View {
        content
            .background(
                DetachedSheetUpdater(
                    isPresented: isPresented,
                    content: AnyView(sheetContent()),
                    controller: controller
                )
            )
            .onDisappear {
                controller.destroy()
            }
    }
}

private struct DetachedSheetUpdater: NSViewRepresentable {
    let isPresented: Bool
    let content: AnyView
    let controller: DetachedSheetController

    func makeNSView(context: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        controller.update(
            isPresented: isPresented,
            parentWindow: nsView.window,
            content: content
        )
    }
}

private final class DimmingWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class DetachedSheetController: ObservableObject {
    private var sheetWindow: NSWindow?
    private var dimmingWindow: NSWindow?
    private var hostingView: NSHostingView<AnyView>?
    private weak var parentWindow: NSWindow?
    private var parentObservers: [NSObjectProtocol] = []

    deinit {
        destroy()
    }

    func update(isPresented: Bool, parentWindow: NSWindow?, content: AnyView) {
        self.parentWindow = parentWindow

        if isPresented {
            if sheetWindow == nil {
                show(parentWindow: parentWindow, content: content)
            } else {
                hostingView?.rootView = content
                updateContentSize()
                centerOnParent()
            }
        } else {
            if sheetWindow != nil {
                destroy()
            }
        }
    }

    func destroy() {
        detachParentObservers()

        if let dimmingWindow {
            parentWindow?.removeChildWindow(dimmingWindow)
            dimmingWindow.orderOut(nil)
            dimmingWindow.close()
        }

        if let sheetWindow {
            parentWindow?.removeChildWindow(sheetWindow)
            sheetWindow.orderOut(nil)
            sheetWindow.close()
        }

        sheetWindow = nil
        dimmingWindow = nil
        hostingView = nil
    }

    private func show(parentWindow: NSWindow?, content: AnyView) {
        guard let parentWindow else { return }

        // -- Dimming window --
        let dimming = DimmingWindow(
            contentRect: parentWindow.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: true
        )
        dimming.isReleasedWhenClosed = false
        dimming.backgroundColor = .clear
        dimming.isOpaque = false
        dimming.hasShadow = false
        dimming.ignoresMouseEvents = false

        let dimmingView = NSView(frame: dimming.contentView!.bounds)
        dimmingView.autoresizingMask = [.width, .height]
        dimmingView.wantsLayer = true
        dimmingView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.3).cgColor
        dimmingView.layer?.cornerRadius = 10
        dimmingView.layer?.cornerCurve = .continuous
        dimming.contentView?.addSubview(dimmingView)

        parentWindow.addChildWindow(dimming, ordered: .above)
        dimming.orderFront(nil)
        self.dimmingWindow = dimming

        // -- Sheet window --
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = true

        let sheet = NSWindow(
            contentRect: .zero,
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        sheet.isReleasedWhenClosed = false
        sheet.contentView = hostingView
        sheet.title = ""
        sheet.hasShadow = true
        sheet.isMovable = false
        sheet.isMovableByWindowBackground = false
        sheet.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]

        sheet.standardWindowButton(.closeButton)?.isHidden = true
        sheet.standardWindowButton(.miniaturizeButton)?.isHidden = true
        sheet.standardWindowButton(.zoomButton)?.isHidden = true

        self.sheetWindow = sheet
        self.hostingView = hostingView

        updateContentSize()

        parentWindow.addChildWindow(sheet, ordered: .above)
        centerOnParent()
        sheet.makeKeyAndOrderFront(nil)

        attachParentObservers()
    }

    private func updateContentSize() {
        guard let sheetWindow, let hostingView else { return }

        hostingView.layoutSubtreeIfNeeded()
        let fitting = hostingView.fittingSize
        let size = CGSize(
            width: max(fitting.width, 1),
            height: max(fitting.height, 1)
        )

        hostingView.setFrameSize(size)
        sheetWindow.setContentSize(size)
    }

    private func centerOnParent() {
        guard let sheetWindow, let parentWindow else { return }

        let parentFrame = parentWindow.frame
        let sheetSize = sheetWindow.frame.size

        let x = parentFrame.midX - sheetSize.width / 2
        let y = parentFrame.midY - sheetSize.height / 2

        sheetWindow.setFrameOrigin(CGPoint(x: x, y: y))
    }

    private func updateDimmingFrame() {
        guard let dimmingWindow, let parentWindow else { return }
        dimmingWindow.setFrame(parentWindow.frame, display: true)
    }

    private func attachParentObservers() {
        detachParentObservers()
        guard let parentWindow else { return }

        let center = NotificationCenter.default

        parentObservers.append(
            center.addObserver(
                forName: NSWindow.didResizeNotification,
                object: parentWindow,
                queue: .main
            ) { [weak self] _ in
                self?.updateDimmingFrame()
                self?.centerOnParent()
            }
        )
    }

    private func detachParentObservers() {
        guard !parentObservers.isEmpty else { return }
        let center = NotificationCenter.default
        parentObservers.forEach { center.removeObserver($0) }
        parentObservers.removeAll()
    }
}
#endif
