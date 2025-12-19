//
//  HIDIOController.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/11/25.
//

import Foundation

import SiriusKitClient

class HIDIOController {
    private let channel: HIDIOChannel
    private var devices: [HIDIOVirtualDeviceKind: HIDIOVirtualDevice] = [:]
    
    init(channel: HIDIOChannel) {
        self.channel = channel
    }
    
    func connect(_ device: HIDIOVirtualDevice) {
        let kind = type(of: device).kind
        
        self.disconnect(kind: kind)
        device.connect(to: self)
        
        self.devices[kind] = device
    }
    
    func disconnect(kind: HIDIOVirtualDeviceKind) {
        guard let device = self.devices[kind] else {
            return
        }
        
        device.disconnect()
    }
    
    func keyDown(keyCode: LinuxKeycode) async throws {
        let event = KeyboardEvent(
            eventType: .down,
            scanCode: 0,
            keyCode: UInt32(keyCode.rawValue),
            modifiers: 0,
            flags: 0
        )
        
        let packet = HIDIOPacket(sequenceNumber: 0, timestamp: 0, events: [
            HIDEvent(event: .keyboardEvent(event))
        ])
        
        try await self.channel.send(opcode: .hidioPacket, message: packet)
    }
    
    func keyUp(keyCode: LinuxKeycode) async throws {
        let event = KeyboardEvent(
            eventType: .up,
            scanCode: 0,
            keyCode: UInt32(keyCode.rawValue),
            modifiers: 0,
            flags: 0
        )
        
        let packet = HIDIOPacket(sequenceNumber: 0, timestamp: 0, events: [
            HIDEvent(event: .keyboardEvent(event))
        ])
        
        try await self.channel.send(opcode: .hidioPacket, message: packet)
    }
}
