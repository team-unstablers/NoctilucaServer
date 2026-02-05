//
//  HIDIOAppKitMouseView.swift
//  NoctilucaClient
//
//  Created by Codex on 2/5/26.
//

#if os(macOS)
import AppKit
import SwiftUI

import SiriusKitClient

struct HIDIOAppKitMouseView: View {
    let pointer: HIDIOAppKitPointer

    var body: some View {
        HIDIOAppKitMouseCaptureView(pointer: pointer)
    }
}

private struct HIDIOAppKitMouseCaptureView: NSViewRepresentable {
    let pointer: HIDIOAppKitPointer

    func makeNSView(context: Context) -> MouseInputCaptureView {
        MouseInputCaptureView(pointer: pointer)
    }

    func updateNSView(_ nsView: MouseInputCaptureView, context: Context) {
        nsView.updatePointer(pointer)
    }
}

private final class MouseInputCaptureView: NSView {
    private var pointer: HIDIOAppKitPointer
    private var trackingArea: NSTrackingArea?

    init(pointer: HIDIOAppKitPointer) {
        self.pointer = pointer
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    func updatePointer(_ pointer: HIDIOAppKitPointer) {
        self.pointer = pointer
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let options: NSTrackingArea.Options = [
            .mouseEnteredAndExited,
            .mouseMoved,
            .activeInActiveApp,
            .inVisibleRect
        ]

        let newTrackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    override func mouseMoved(with event: NSEvent) {
        handleMoveEvent(event)
    }

    override func mouseDragged(with event: NSEvent) {
        handleMoveEvent(event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        handleMoveEvent(event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        handleMoveEvent(event)
    }

    override func mouseDown(with event: NSEvent) {
        handleMoveEvent(event)
        pointer.buttonDown(.left)
    }

    override func mouseUp(with event: NSEvent) {
        pointer.buttonUp(.left)
    }

    override func rightMouseDown(with event: NSEvent) {
        handleMoveEvent(event)
        pointer.buttonDown(.right)
    }

    override func rightMouseUp(with event: NSEvent) {
        pointer.buttonUp(.right)
    }

    override func otherMouseDown(with event: NSEvent) {
        guard let button = mapButtonNumber(Int(event.buttonNumber)) else {
            return
        }

        handleMoveEvent(event)
        pointer.buttonDown(button)
    }

    override func otherMouseUp(with event: NSEvent) {
        guard let button = mapButtonNumber(Int(event.buttonNumber)) else {
            return
        }

        pointer.buttonUp(button)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta: CGPoint
        if event.hasPreciseScrollingDeltas {
            delta = CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY)
        } else {
            delta = CGPoint(x: event.deltaX * 10.0, y: event.deltaY * 10.0)
        }

        handleMoveEvent(event)
        pointer.scroll(delta: delta)
    }

    private func normalizedLocation(for event: NSEvent) -> CGPoint? {
        guard bounds.width > 0.0, bounds.height > 0.0 else {
            return nil
        }

        let location = convert(event.locationInWindow, from: nil)
        return CGPoint(
            x: location.x / bounds.width,
            y: 1.0 - location.y / bounds.height
        )
    }

    private func handleMoveEvent(_ event: NSEvent) {
        guard let normalized = normalizedLocation(for: event) else {
            return
        }

        pointer.moveAbsolute(to: normalized)
    }

    private func mapButtonNumber(_ number: Int) -> MouseButtonType? {
        switch number {
        case 0:
            return .left
        case 1:
            return .right
        case 2:
            return .middle
        case 3:
            return .back
        case 4:
            return .forward
        default:
            return nil
        }
    }
}
#endif
