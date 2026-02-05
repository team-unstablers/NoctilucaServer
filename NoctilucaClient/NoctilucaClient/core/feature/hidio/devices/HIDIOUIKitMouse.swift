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
final class HIDIOUIKitMouse: HIDIOVirtualDevice {
    static let kind: HIDIOVirtualDeviceKind = .mouse
    static let identifier: HIDIOVirtualDeviceIdentifier = .uiKitPointer

    private let logger = NoctilucaLogger(category: "HIDIOUIKitMouse")

    private weak var controller: HIDIOController?
    private weak var router: PointerInputRouter?

    private var geometry: CGSize = .zero

    func connect(to controller: HIDIOController) {
        self.controller = controller
        self.router = controller.pointerInputRouter
    }

    func disconnect() {
        self.controller = nil
        self.router = nil
    }

    func updateGeometry(_ size: CGSize) {
        geometry = size
    }

    func moveAbsolute(to point: CGPoint) {
        guard let normalized = normalizedPoint(point) else {
            logger.debug("Invalid geometry, skipping absolute move")
            return
        }

        if let router {
            router.moveMouseAbsolutePercentage(from: .touch, to: normalized)
        } else {
            controller?.moveMouseAbsolutePercentage(to: normalized)
        }
    }

    func moveRelative(by delta: CGPoint) {
        if let router {
            router.moveMouseRelative(from: .touch, by: delta)
        } else {
            controller?.moveMouseRelative(to: delta)
        }
    }

    func moveRelativePercentage(by delta: CGPoint) {
        guard let normalized = normalizedDelta(delta) else {
            logger.debug("Invalid geometry, skipping relative percentage move")
            return
        }
        
        if let router {
            router.moveMouseRelativePercentage(from: .touch, by: normalized)
        } else {
            controller?.moveMouseRelativePercentage(to: normalized)
        }
    }

    func buttonDown(_ button: MouseButtonType) {
        if let router {
            router.mouseButtonDown(from: .touch, button: button)
        } else {
            controller?.mouseButtonDown(button: button)
        }
    }

    func buttonUp(_ button: MouseButtonType) {
        if let router {
            router.mouseButtonUp(from: .touch, button: button)
        } else {
            controller?.mouseButtonUp(button: button)
        }
    }

    func scroll(delta: CGPoint) {
        if let router {
            router.mouseWheel(from: .touch, delta: delta)
        } else {
            controller?.mouseWheel(delta: delta)
        }
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
