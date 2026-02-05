//
//  HIDIOController.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/11/25.
//

import Foundation
import Atomics

import AsyncAlgorithms

import SiriusKitClient


class HIDIOController {
    class KeyPressState {
        private(set) var pressedKeys: Set<LinuxKeycode> = []
        
        func keyDown(_ keyCode: LinuxKeycode) {
            pressedKeys.insert(keyCode)
        }
        
        func keyUp(_ keyCode: LinuxKeycode) {
            pressedKeys.remove(keyCode)
        }
        
        func reset() {
            pressedKeys.removeAll()
        }
    }
    
    private let logger = NoctilucaLogger(category: "HIDIOController")
    
    private let settingsStore: SettingsStore = .shared
    
    private let channel: HIDIOChannel
    private var devices: [HIDIOVirtualDeviceIdentifier: HIDIOVirtualDevice] = [:]

    var pointerInputRouter: PointerInputRouter?
    
    private let eventStream: AsyncStream<HIDEvent>
    private let eventStreamContinuation: AsyncStream<HIDEvent>.Continuation
    
    private var publisherTask: Task<Void, Never>? = nil
    private let requestCounter = ManagedAtomic<UInt64>(0)
    
    private(set) var keyPressState = KeyPressState()
    private(set) var keystrokeHooks: [HIDIOKeystrokeHookIdentifier: HIDIOKeystrokeHook] = [:]

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
    
    /// 다음 request ID를 생성합니다.
    func nextRequestID() -> UInt64 {
        requestCounter.loadThenWrappingIncrement(ordering: .relaxed)
    }   
        
    private func publisherTaskMain() async {
        // TODO: 폴링 레이트 설정 가능해야 함
        // 120Hz로 폴링
        let pollingRate = 60.0
        
        for await chunks in self.eventStream.chunked(by: .repeating(every: .milliseconds(1000 / pollingRate), clock: .suspending)) {
            if chunks.isEmpty {
                continue
            }
            
            if chunks.count >= 2 {
                logger.info("Sending HID event batch with \(chunks.count) events")
            }
            
            let packet = HIDIOPacket(
                sequenceNumber: nextRequestID(),
                timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                events: Array(chunks)
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
        
        if let lockableDevice = device as? HIDIOLockableVirtualDevice {
            try? lockableDevice.unlock()
        }

        device.disconnect()
        self.devices.removeValue(forKey: identifier)
    }
    
    func disconnectAll(kind: HIDIOVirtualDeviceKind) {
        let devicesToDisconnect = self.devices.filter { type(of: $0.value).kind == kind }
        
        for (identifier, device) in devicesToDisconnect {
            if let lockableDevice = device as? HIDIOLockableVirtualDevice {
                try? lockableDevice.unlock()
            }

            device.disconnect()
            self.devices.removeValue(forKey: identifier)
        }
    }
    
    func keyDown(keyCode: LinuxKeycode) {
        let event = KeyboardEvent(
            eventType: .keyDown,
            scanCode: 0,
            keyCode: UInt32(keyCode.rawValue),
            modifiers: 0,
            flags: 0
        )
        
        self.eventStreamContinuation.yield(event)
        self.keyPressState.keyDown(keyCode)
        
        self.evaluateHooks()
    }
    
    func keyUp(keyCode: LinuxKeycode) {
        let event = KeyboardEvent(
            eventType: .keyUp,
            scanCode: 0,
            keyCode: UInt32(keyCode.rawValue),
            modifiers: 0,
            flags: 0
        )
        
        self.eventStreamContinuation.yield(event)
        self.keyPressState.keyUp(keyCode)
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

extension HIDIOController {
    func installHook(_ hook: HIDIOKeystrokeHook, for identifier: HIDIOKeystrokeHookIdentifier) {
        self.keystrokeHooks[identifier] = hook
    }
    
    func removeHook(for identifier: HIDIOKeystrokeHookIdentifier) {
        self.keystrokeHooks.removeValue(forKey: identifier)
    }
    
    private func evaluateHooks() {
        let state = self.keyPressState
        
        for hook in self.keystrokeHooks.values {
            if hook.evaluate(state) {
                hook.action()
            }
        }
    }
}
