//
//  HIDIOController.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/11/25.
//

import Foundation

import AsyncAlgorithms

import SiriusKitClient


class HIDIOController {
    private let logger = NoctilucaLogger(category: "HIDIOController")
    
    private let channel: HIDIOChannel
    private var devices: [HIDIOVirtualDeviceIdentifier: HIDIOVirtualDevice] = [:]
    
    private let eventStream: AsyncStream<HIDEvent>
    private let eventStreamContinuation: AsyncStream<HIDEvent>.Continuation
    
    private var publisherTask: Task<Void, Never>? = nil

    init(channel: HIDIOChannel) {
        self.channel = channel
        
        var continuation: AsyncStream<HIDEvent>.Continuation!
        self.eventStream = AsyncStream<HIDEvent> { cont in
            continuation = cont
        }
        
        self.eventStreamContinuation = continuation
        
        self.publisherTask = Task {
            await self.publisherTaskMain()
        }
    }
    
    deinit {
        self.publisherTask?.cancel()
    }
        
    private func publisherTaskMain() async {
        // TODO: 폴링 레이트 설정 가능해야 함
        // 120Hz로 폴링
        let pollingRate = 120.0
        
        for await chunks in self.eventStream.chunked(by: .repeating(every: .milliseconds(1000 / pollingRate), clock: .suspending)) {
            
            if chunks.isEmpty {
                continue
            }
            
            if chunks.count >= 2 {
                logger.info("Sending HID event batch with \(chunks.count) events")
            }
            
            let packet = HIDIOPacket(
                sequenceNumber: 0,
                timestamp: 0,
                events: chunks
            )
            
            do {
                try await channel.send(opcode: .hidioPacket, message: consume packet)
            } catch {
                logger.error("Failed to send HID event batch: \(error)")
            }
        }
    }
    
    func connect(_ device: HIDIOVirtualDevice) {
        let identifier = type(of: device).identifier
        
        self.disconnect(identifier)
        device.connect(to: self)
        
        self.devices[identifier] = device
    }
    
    func device(for identifier: HIDIOVirtualDeviceIdentifier) -> HIDIOVirtualDevice? {
        return self.devices[identifier]
    }

    func devices(for kind: HIDIOVirtualDeviceKind) -> [HIDIOVirtualDevice] {
        let devices = self.devices.filter { type(of: $0.value).kind == kind }.compactMap { $0.value }
        return devices
    }
    
    func disconnect(_ identifier: HIDIOVirtualDeviceIdentifier) {
        guard let device = self.devices[identifier] else {
            return
        }
        
        device.disconnect()
        self.devices.removeValue(forKey: identifier)
    }
    
    func disconnectAll(kind: HIDIOVirtualDeviceKind) {
        let devicesToDisconnect = self.devices.filter { type(of: $0.value).kind == kind }
        
        for (identifier, device) in devicesToDisconnect {
            device.disconnect()
            self.devices.removeValue(forKey: identifier)
        }
    }
    
    func keyDown(keyCode: LinuxKeycode) {
        let event = KeyboardEvent(
            eventType: .down,
            scanCode: 0,
            keyCode: UInt32(keyCode.rawValue),
            modifiers: 0,
            flags: 0
        )
        
        self.eventStreamContinuation.yield(event)
    }
    
    func keyUp(keyCode: LinuxKeycode) {
        let event = KeyboardEvent(
            eventType: .up,
            scanCode: 0,
            keyCode: UInt32(keyCode.rawValue),
            modifiers: 0,
            flags: 0
        )
        
        self.eventStreamContinuation.yield(event)
    }
    
    func moveMouseAbsolutePercentage(to position: CGPoint) {
        let event = MouseMoveEvent(
            moveType: .absolute,
            // TODO: setMouseScope(...) 같은거 필요하고, 프로젝션 윈도우에서 능동적으로 호출해야 함
            scope: .displayId(-1),
            position: .percent(CursorPositionPercent(x: Float(position.x), y: Float(position.y)))
        )
        
        self.eventStreamContinuation.yield(event)
    }
    
    func moveMouseRelative(to position: CGPoint) {
        let event = MouseMoveEvent(
            moveType: .relative,
            // TODO: setMouseScope(...) 같은거 필요하고, 프로젝션 윈도우에서 능동적으로 호출해야 함
            scope: .displayId(-1),
            position: .pixel(CursorPositionPixel(x: Int32(position.x), y: Int32(position.y)))
        )
        
        self.eventStreamContinuation.yield(event)
    }
    
    func moveMouseRelativePercentage(to position: CGPoint) {
        let event = MouseMoveEvent(
            moveType: .relative,
            // TODO: setMouseScope(...) 같은거 필요하고, 프로젝션 윈도우에서 능동적으로 호출해야 함
            scope: .displayId(-1),
            position: .percent(CursorPositionPercent(x: Float(position.x), y: Float(position.y)))
        )
        
        self.eventStreamContinuation.yield(event)
    }
    
    func mouseButtonDown(button: MouseButtonType) {
        let event = MouseButtonEvent(
            eventType: .down,
            button: button
        )
        
        self.eventStreamContinuation.yield(event)
    }
    
    func mouseButtonUp(button: MouseButtonType) {
        let event = MouseButtonEvent(
            eventType: .up,
            button: button
        )
        
        self.eventStreamContinuation.yield(event)
    }
    
    func mouseWheel(delta: CGPoint) {
        let event = MouseWheelEvent(
            deltaX: Float(delta.x),
            deltaY: Float(delta.y)
        )
        
        self.eventStreamContinuation.yield(event)
    }
}
