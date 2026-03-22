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

    private var invertMouseButtons: Bool = false
    private var invertVerticalScroll: Bool = false
    private var invertHorizontalScroll: Bool = false
    private var mouseScrollMultiplier: Double = 1.0

    private let channel: Weak<HIDIOChannel>
    private var devices: [String: HIDIOVirtualDevice] = [:]

    private let eventStream: AsyncStream<HIDEvent>
    private let eventStreamContinuation: AsyncStream<HIDEvent>.Continuation
    
    private var publisherTask: Task<Void, Never>? = nil
    private let requestCounter = ManagedAtomic<UInt64>(0)
    
    let keyEventPipeline = KeyEventPipelineChain()

    private(set) var keyPressState = KeyPressState()
    private(set) var keystrokeHooks: [HIDIOKeystrokeHookIdentifier: HIDIOKeystrokeHook] = [:]
    
    init(channel: HIDIOChannel) {
        self.channel = Weak(channel)
        
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
        for await event in self.eventStream {
            let packet = HIDIOPacket(
                sequenceNumber: nextRequestID(),
                timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                events: [event]
            )
            
            do {
                try await channel.ref.send(opcode: .hidioPacket, message: consume packet)
            } catch {
                logger.error("Failed to send HID event batch: \(error)")
            }
        }
    }
    
    func connect(_ device: HIDIOVirtualDevice) {
        let identifier = device.identifierString
        
        self.disconnect(identifier)
        device.connect(to: self)
        
        self.devices[identifier] = device
    }
    
    func device(for identifier: String) -> HIDIOVirtualDevice? {
        return self.devices[identifier]
    }

    func devices(for kind: HIDIOVirtualDeviceKind) -> [HIDIOVirtualDevice] {
        let devices = self.devices.filter { type(of: $0.value).kind == kind }.compactMap { $0.value }
        return devices
    }
    
    func disconnect(_ identifier: HIDIOVirtualDeviceIdentifier) {
        guard let device = self.devices[identifier.rawValue.uuidString] else {
            return
        }

        device.disconnect()
        self.devices.removeValue(forKey: identifier.rawValue.uuidString)
    }
    
    func disconnect(_ identifierString: String) {
        guard let device = self.devices[identifierString] else {
            return
        }

        device.disconnect()
        self.devices.removeValue(forKey: identifierString)
    }
    
    func disconnectAll(kind: HIDIOVirtualDeviceKind) {
        let devicesToDisconnect = self.devices.filter { type(of: $0.value).kind == kind }
        
        for (identifier, device) in devicesToDisconnect {
            device.disconnect()
            self.devices.removeValue(forKey: identifier)
        }
    }

    func resetKeyPressState() {
        let pressedKeys = Array(keyPressState.pressedKeys)
        for key in pressedKeys {
            keyUp(keyCode: key)
        }
        keyPressState.reset()
    }
    
    func sendKeyboardSetup(hacks: [KeyboardHack]) {
        let event = KeyboardSetupEvent(
            preferredLayouts: [],
            hacks: hacks,
            flags: 0
        )
        self.eventStreamContinuation.yield(event)
    }

    func keyDown(keyCode: LinuxKeycode) {
        self.keyPressState.keyDown(keyCode)
        self.evaluateHooks()

        let event = KeyboardEvent(
            eventType: .keyDown,
            scanCode: 0,
            keyCode: UInt32(keyCode.rawValue),
            modifiers: 0,
            flags: 0
        )

        if let processed = keyEventPipeline.process(event) {
            self.eventStreamContinuation.yield(processed)
        }
    }

    func keyUp(keyCode: LinuxKeycode) {
        self.keyPressState.keyUp(keyCode)

        let event = KeyboardEvent(
            eventType: .keyUp,
            scanCode: 0,
            keyCode: UInt32(keyCode.rawValue),
            modifiers: 0,
            flags: 0
        )

        if let processed = keyEventPipeline.process(event) {
            self.eventStreamContinuation.yield(processed)
        }
    }

    /// UCS4 코드포인트를 직접 전송합니다. CJK 등 keycode 매핑이 불가능한 문자에 사용됩니다.
    func sendUCS4(_ codepoint: UInt32) {
        let event = KeyboardEvent(
            eventType: .ucs4,
            scanCode: 0,
            keyCode: codepoint,
            modifiers: 0,
            flags: 0
        )

        self.eventStreamContinuation.yield(event)
    }
    
    func moveMouseAbsolutePercentage(to position: CGPoint, on scope: CursorPositionScope = .displayId(-1), pressure: Int32? = nil) {
        let event = MouseMoveEvent(
            moveType: .absolute,
            // TODO: setMouseScope(...) 같은거 필요하고, 프로젝션 윈도우에서 능동적으로 호출해야 함
            scope: scope,
            position: .percent(CursorPositionPercent(x: Float(position.x), y: Float(position.y))),
            pressure: pressure
        )

        self.eventStreamContinuation.yield(event)
    }
    
    func moveMouseRelative(to position: CGPoint, on scope: CursorPositionScope = .displayId(-1)) {
        let event = MouseMoveEvent(
            moveType: .relative,
            // TODO: setMouseScope(...) 같은거 필요하고, 프로젝션 윈도우에서 능동적으로 호출해야 함
            scope: scope,
            position: .pixel(CursorPositionPixel(x: Int32(position.x), y: Int32(position.y)))
        )
        
        self.eventStreamContinuation.yield(event)
    }
    
    func moveMouseRelativePercentage(to position: CGPoint, on scope: CursorPositionScope = .displayId(-1)) {
        let event = MouseMoveEvent(
            moveType: .relative,
            // TODO: setMouseScope(...) 같은거 필요하고, 프로젝션 윈도우에서 능동적으로 호출해야 함
            scope: scope,
            position: .percent(CursorPositionPercent(x: Float(position.x), y: Float(position.y)))
        )
        
        self.eventStreamContinuation.yield(event)
    }
    
    func applyMouseInputSettings(_ input: AppSettings.Input) {
        self.invertMouseButtons = input.invertMouseButtons
        self.invertVerticalScroll = input.invertVerticalScroll
        self.invertHorizontalScroll = input.invertHorizontalScroll
        self.mouseScrollMultiplier = input.mouseScrollMultiplier
    }

    func mouseButtonDown(button: MouseButtonType) {
        var actualButton = button
        if invertMouseButtons {
            if button == .left { actualButton = .right }
            else if button == .right { actualButton = .left }
        }

        let event = MouseButtonEvent(
            eventType: .down,
            button: actualButton
        )

        self.eventStreamContinuation.yield(event)
    }

    func mouseButtonUp(button: MouseButtonType) {
        var actualButton = button
        if invertMouseButtons {
            if button == .left { actualButton = .right }
            else if button == .right { actualButton = .left }
        }

        let event = MouseButtonEvent(
            eventType: .up,
            button: actualButton
        )

        self.eventStreamContinuation.yield(event)
    }

    func mouseWheel(delta: CGPoint) {
        var deltaX = Float(delta.x)
        var deltaY = Float(delta.y)

        if invertHorizontalScroll { deltaX = -deltaX }
        if invertVerticalScroll { deltaY = -deltaY }

        let scrollMul = Float(mouseScrollMultiplier)
        deltaX *= scrollMul
        deltaY *= scrollMul

        let event = MouseWheelEvent(
            deltaX: deltaX,
            deltaY: deltaY
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
