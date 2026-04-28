//
//  HIDIOAppKitMouse.swift
//  NoctilucaClient
//
//  Created by Codex on 1/29/26.
//

import Foundation
import CoreGraphics

import SiriusKitClient

extension HIDIOVirtualDeviceIdentifier {
    /// AppKit NSView를 통해 포인터 입력을 처리하는 가상 디바이스.
    @available(iOS, unavailable)
    static let appKitMouse = Self(rawValue: UUID(uuidString: "ADBD6DE0-517E-4E4B-AAC6-EC9C7E814E95")!)
}

@available(iOS, unavailable)
@MainActor
final class HIDIOAppKitPointer: HIDIOVirtualDevice {
    static let kind: HIDIOVirtualDeviceKind = .mouse
    static let identifier: HIDIOVirtualDeviceIdentifier = .appKitMouse

    private let logger = NoctilucaLogger(category: "HIDIOAppKitMouse")

    private weak var controller: HIDIOController?
    
    var localIdentifier: String? = nil

    var scope: CursorPositionScope = .displayId(-1)
    
    func connect(to controller: HIDIOController) {
        self.controller = controller
    }

    func disconnect() {
        self.controller = nil
    }

    /// Parameters:
    /// - point: 절대 좌표, 뷰포트의 좌측 상단이 (0.0, 00), 우측 하단이 (1.0, 1.0)인 좌표계.
    ///   값이 [0, 1] 범위를 벗어날 수 있으며, 이는 인접 디스플레이로의 cross-display 드래그를
    ///   서버 측 clampToNearestScreen 으로 라우팅하기 위함이다.
    func moveAbsolute(to point: CGPoint) {
        controller?.moveMouseAbsolutePercentage(to: point, on: scope)
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

    private func clampNormalized(_ position: CGPoint) -> CGPoint {
        CGPoint(
            x: min(max(position.x, 0.0), 1.0),
            y: min(max(position.y, 0.0), 1.0)
        )
    }
}
