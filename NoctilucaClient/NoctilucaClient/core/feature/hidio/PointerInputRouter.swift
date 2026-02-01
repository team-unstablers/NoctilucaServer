//
//  PointerInputRouter.swift
//  NoctilucaClient
//
//  Created by Codex on 1/29/26.
//

import Foundation
import CoreGraphics

import SiriusKitClient

enum PointerInputSource {
    case touch
    case hardware
}

final class PointerInputRouter {
    private weak var controller: HIDIOController?
    private(set) var pointerInputMode: AppSettings.PointerInputMode = .automatic
    private(set) var isHardwareMouseConnected: Bool = false
    private(set) var activeSource: PointerInputSource = .touch

    init(controller: HIDIOController) {
        self.controller = controller
    }

    func updateInputMode(_ mode: AppSettings.PointerInputMode) {
        pointerInputMode = mode
        refreshActiveSource()
    }

    func updateHardwareMouseConnected(_ connected: Bool) {
        isHardwareMouseConnected = connected
        refreshActiveSource()
    }

    private func refreshActiveSource() {
        switch pointerInputMode {
        case .touchPointer:
            activeSource = .touch
        case .hardwareMouse:
            activeSource = isHardwareMouseConnected ? .hardware : .touch
        case .automatic:
            activeSource = isHardwareMouseConnected ? .hardware : .touch
        }
    }

    private func shouldRoute(source: PointerInputSource) -> Bool {
        return source == activeSource
    }

    func moveMouseAbsolutePercentage(from source: PointerInputSource, to position: CGPoint) {
        guard shouldRoute(source: source) else {
            return
        }

        controller?.moveMouseAbsolutePercentage(to: position)
    }

    func moveMouseRelative(from source: PointerInputSource, by delta: CGPoint) {
        guard shouldRoute(source: source) else {
            return
        }

        controller?.moveMouseRelative(to: delta)
    }

    func moveMouseRelativePercentage(from source: PointerInputSource, by delta: CGPoint) {
        guard shouldRoute(source: source) else {
            return
        }

        controller?.moveMouseRelativePercentage(to: delta)
    }

    func mouseButtonDown(from source: PointerInputSource, button: MouseButtonType) {
        guard shouldRoute(source: source) else {
            return
        }

        controller?.mouseButtonDown(button: button)
    }

    func mouseButtonUp(from source: PointerInputSource, button: MouseButtonType) {
        guard shouldRoute(source: source) else {
            return
        }

        controller?.mouseButtonUp(button: button)
    }

    func mouseWheel(from source: PointerInputSource, delta: CGPoint) {
        guard shouldRoute(source: source) else {
            return
        }

        controller?.mouseWheel(delta: delta)
    }
}
