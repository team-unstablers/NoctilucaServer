//
//  HIDIOController.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/11/25.
//

import Foundation
import Atomics
import Combine

import AsyncAlgorithms

import SiriusKitClient


@MainActor
final class HIDIOController {
    final class KeyPressState {
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

    private lazy var settingsStore: SettingsStore = {
        .shared
    }()

    private var invertMouseButtons: Bool = false
    private var invertVerticalScroll: Bool = false
    private var invertHorizontalScroll: Bool = false
    private var mouseScrollMultiplier: Double = 1.0

    // v2: 상위 HIDIOChannel 대신 ChannelHandle 을 직접 보유한다.
    private let handle: ChannelHandle
    private var devices: [String: HIDIOVirtualDevice] = [:]

    private let eventStream: AsyncStream<HIDEvent>
    private let eventStreamContinuation: AsyncStream<HIDEvent>.Continuation

    nonisolated(unsafe) private var publisherTask: Task<Void, Never>? = nil
    nonisolated private let requestCounter = ManagedAtomic<UInt64>(0)

    lazy var keyEventPipeline: KeyEventPipelineChain = {
        KeyEventPipelineChain()
    }()

    private(set) var keyPressState = KeyPressState()
    private(set) var keystrokeHooks: [HIDIOKeystrokeHookIdentifier: HIDIOKeystrokeHook] = [:]

    /// 트리거 키 차단 훅이 발동되어 host 로 전달하지 않고 삼킨 keyDown 들의 집합.
    /// 이후 들어오는 keyUp 은 down/up 짝맞춤을 위해 함께 삼킨다.
    private var blockedKeyDowns: Set<LinuxKeycode> = []

    /// 키 상태 변경 시 현재 눌린 키 집합을 방출합니다. (디버그 뷰 용도)
    let keyStateDidChange = PassthroughSubject<Set<LinuxKeycode>, Never>()

    nonisolated init(handle: ChannelHandle) {
        self.handle = handle

        var continuation: AsyncStream<HIDEvent>.Continuation!
        self.eventStream = AsyncStream<HIDEvent> { cont in
            continuation = cont
        }

        self.eventStreamContinuation = continuation

        self.publisherTask = Task { [weak self] in
            await self?.publisherTaskMain()
        }
    }

    deinit {
        // MainActor-isolated 자산이지만 AsyncStream.Continuation.finish() 와
        // Task.cancel() 은 Sendable 메서드이므로 nonisolated deinit 에서도 호출 가능.
        eventStreamContinuation.finish()
        publisherTask?.cancel()
    }

    func shutdown() {
        eventStreamContinuation.finish()
        publisherTask?.cancel()
        publisherTask = nil
    }

    /// 다음 request ID를 생성합니다.
    nonisolated func nextRequestID() -> UInt64 {
        requestCounter.loadThenWrappingIncrement(ordering: .relaxed)
    }

    private func publisherTaskMain() async {
        // MainActor-inherited Task 이므로 이 루프 역시 main thread 에서 실행된다.
        // handle.send(nonblocking:) 은 atomic fast-path 로 lock-free enqueue 만
        // 수행하므로, main thread 를 블로킹하지 않는다.
        for await event in self.eventStream {
            let packet = HIDIOPacket(
                sequenceNumber: nextRequestID(),
                timestamp: UInt64(Date().timeIntervalSince1970 * 1000),
                events: [event]
            )

            handle.send(nonblocking: .hidioPacket, message: consume packet)
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

    /// 현재 눌린 키 상태를 모두 초기화합니다.
    ///
    /// - Parameter emittingKeyUpEvents: `true` (기본값) 이면 눌려있던 모든 키에
    ///   대해 host 로 keyUp 이벤트를 전송한다 — 세션 종료 / 윈도우 비활성화 등에서
    ///   host 측 키 stuck 을 방지하기 위함. `false` 이면 host 로 keyUp 을 전송
    ///   하지 않고 internal state 만 비운다 — 모드 전환처럼, 사용자가 실제로
    ///   modifier 키를 떼는 시점에 새 입력 디바이스를 통해 자연스럽게 keyUp 이
    ///   전달되는 것을 기대하는 경우에 사용.
    func resetKeyPressState(emittingKeyUpEvents: Bool = true) {
        if emittingKeyUpEvents {
            let pressedKeys = Array(keyPressState.pressedKeys)
            for key in pressedKeys {
                keyUp(keyCode: key)
            }
        }
        keyPressState.reset()
        blockedKeyDowns.removeAll()
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
        let swallowedTriggerKeys = self.evaluateHooks()
        self.keyStateDidChange.send(keyPressState.pressedKeys)

        if swallowedTriggerKeys.contains(keyCode) {
            // 트리거 키 down 은 host 로 전달하지 않고 삼킨다.
            // 이후 들어오는 keyUp 도 짝맞춤을 위해 함께 삼킨다.
            blockedKeyDowns.insert(keyCode)
            return
        }

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
        self.keyStateDidChange.send(keyPressState.pressedKeys)

        if blockedKeyDowns.remove(keyCode) != nil {
            // 동일 키의 down 을 차단했으므로 host 의 down/up 짝맞춤을 위해 up 도 차단.
            return
        }

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

    func moveMouseAbsolutePercentage(to position: CGPoint, on scope: CursorPositionScope = .displayId(-1)) {
        let event = MouseMoveEvent(
            moveType: .absolute,
            // TODO: setMouseScope(...) 같은거 필요하고, 프로젝션 윈도우에서 능동적으로 호출해야 함
            scope: scope,
            position: .percent(CursorPositionPercent(x: Float(position.x), y: Float(position.y)))
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

    /// 현재 눌린 키 상태를 기준으로 등록된 훅들을 평가한다.
    /// 훅 액션이 호출되며, `swallowsTriggerKey == true` 인 발동 훅들의
    /// `condition.key` 집합을 반환한다 — 이 키들은 host 로 전달되지 않는다.
    @discardableResult
    private func evaluateHooks() -> Set<LinuxKeycode> {
        let state = self.keyPressState
        var swallowedTriggerKeys: Set<LinuxKeycode> = []

        for hook in self.keystrokeHooks.values where hook.evaluate(state) {
            hook.action()
            if hook.swallowsTriggerKey {
                swallowedTriggerKeys.insert(hook.condition.key)
            }
        }

        return swallowedTriggerKeys
    }
}
