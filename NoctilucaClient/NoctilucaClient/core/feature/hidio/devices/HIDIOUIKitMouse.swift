//
//  HIDIOUIKitPointer.swift
//  NoctilucaClient
//
//  Created by Codex on 1/29/26.
//

import Foundation
import CoreGraphics

import SiriusKitClient

extension HIDIOVirtualDeviceIdentifier {
    /// UIKit 제스처로 포인터 입력을 처리하는 가상 디바이스.
    @available(macOS, unavailable)
    static let uiKitPointer = Self(rawValue: UUID(uuidString: "9A6A06A9-1D1F-4A24-8D5A-902F879A3F4E")!)
}

@available(macOS, unavailable)
@MainActor
final class HIDIOUIKitMouse: HIDIOVirtualDevice {
    static let kind: HIDIOVirtualDeviceKind = .mouse
    static let identifier: HIDIOVirtualDeviceIdentifier = .uiKitPointer

    private let logger = NoctilucaLogger(category: "HIDIOUIKitMouse")

    private weak var controller: HIDIOController?

    private var geometry: CGSize = .zero

    var scope: CursorPositionScope = .displayId(-1)
    
    var localIdentifier: String? { nil }

    func connect(to controller: HIDIOController) {
        self.controller = controller
    }

    func disconnect() {
        self.controller = nil
    }

    func updateGeometry(_ size: CGSize) {
        geometry = size
    }

    func moveAbsolute(to point: CGPoint) {
        guard let normalized = normalizedPoint(point) else {
            logger.debug("Invalid geometry, skipping absolute move")
            return
        }

        controller?.moveMouseAbsolutePercentage(to: normalized, on: scope)
    }

    func moveRelative(by delta: CGPoint) {
        controller?.moveMouseRelative(to: delta)
    }

    func moveRelativePercentage(by delta: CGPoint) {
        guard let normalized = normalizedDelta(delta) else {
            logger.debug("Invalid geometry, skipping relative percentage move")
            return
        }
        
        controller?.moveMouseRelativePercentage(to: normalized)
    }

    func buttonDown(_ button: MouseButtonType) {
        controller?.mouseButtonDown(button: button)
    }

    func buttonUp(_ button: MouseButtonType) {
        controller?.mouseButtonUp(button: button)
    }

    func scroll(delta: CGPoint) {
        controller?.mouseWheel(delta: delta)
    }

    private func normalizedPoint(_ point: CGPoint) -> CGPoint? {
        guard geometry.width > 0.0, geometry.height > 0.0 else {
            return nil
        }

        return CGPoint(x: point.x / geometry.width, y: point.y / geometry.height)
    }

    private func normalizedDelta(_ delta: CGPoint) -> CGPoint? {
        guard geometry.width > 0.0, geometry.height > 0.0 else {
            return nil
        }

        return CGPoint(x: delta.x / geometry.width, y: delta.y / geometry.height)
    }

    private func clampNormalized(_ position: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(position.x, 0.0), 1.0),
            y: min(max(position.y, 0.0), 1.0)
        )
    }
}
