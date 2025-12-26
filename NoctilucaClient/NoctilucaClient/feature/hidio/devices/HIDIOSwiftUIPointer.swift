//
//  HIDIOGCKeyboard.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/18/25.
//

import Foundation
import CoreGraphics

import Combine

import SiriusKitClient

extension HIDIOVirtualDeviceIdentifier {
    /// SwiftUI의 .onTapGesture, .onHover 등을 사용한 마우스 가상 디바이스.
    static let swiftUIMouse = Self(rawValue: UUID(uuidString: "D2B3CBCF-ED5F-4595-B54B-7491301ECFC7")!)
}

class HIDIOSwiftUIMouse: HIDIOVirtualDevice {
    static let kind: HIDIOVirtualDeviceKind = .mouse
    static let identifier: HIDIOVirtualDeviceIdentifier = .swiftUIMouse
    
    private let logger = NoctilucaLogger(category: "HIDIOSwiftUIMouse")
  
    private var controller: HIDIOController?
    
    var geometry: CGSize = .zero

    init() {
    }
    
    deinit {
        self.disconnect()
    }
    
    func setGeometry(_ size: CGSize) {
        self.geometry = size
    }
    
    func reportMouseMove(_ point: CGPoint) {
        guard let controller else {
            logger.debug("No controller connected, skipping mouse move report")
            return
        }
        
        let x = point.x / geometry.width
        let y = point.y / geometry.height
        
        controller.moveMouseAbsolutePercentage(to: CGPoint(x: x, y: y))
    }
    
    func reportMouseClick(button: MouseButtonType, isPressed: Bool) {
        guard let controller else {
            logger.debug("No controller connected, skipping mouse click report")
            return
        }
        
        if isPressed {
            controller.mouseButtonDown(button: button)
        } else {
            controller.mouseButtonUp(button: button)
        }
    }
    
    func reportMouseScroll(deltaX: Double, deltaY: Double) {
        guard let controller else {
            logger.debug("No controller connected, skipping mouse click report")
            return
        }
        
        controller.mouseWheel(delta: CGPoint(x: deltaX, y: deltaY))
    }
   
    func connect(to controller: HIDIOController) {
        self.controller = controller
    }
    
    func disconnect() {
        self.controller = nil
    }
}
