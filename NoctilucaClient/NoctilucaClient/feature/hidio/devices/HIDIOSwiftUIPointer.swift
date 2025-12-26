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

class HIDIOSwiftUIPointer: HIDIOVirtualDevice {
    static let kind: HIDIOVirtualDeviceKind = .pointer
    
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
   
    func connect(to controller: HIDIOController) {
        self.controller = controller
    }
    
    func disconnect() {
        self.controller = nil
    }
}
