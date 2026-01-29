//
//  EventInjector.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/11/25.
//

import Foundation

import Carbon
import Cocoa
import CoreGraphics

import SiriusKit


enum EventInjectorError: LocalizedError {
    case initializationError

    var errorDescription: String? {
        switch (self) {
        case .initializationError:
            return "could not initialize EventInjector instance. (insufficient permission?)"
        }
    }
}

class EventInjector {
    public static let MOUSE_DOWN_STATE_LEFT: UInt16 = 0b1
    public static let MOUSE_DOWN_STATE_RIGHT: UInt16 = 0b10

    public let serialQueue = DispatchQueue(label: "EventInjector", qos: .userInteractive)
    private let serialQueueKey = DispatchSpecificKey<Void>()

    var eventSource: CGEventSource!

    var keyDownState = Set<Int>()
    var repeatableKeysInOrder: [Int] = []
    var repeatKey: Int? = nil
    var repeatTimer: DispatchSourceTimer? = nil
    var repeatDelay: TimeInterval = 0
    var repeatInterval: TimeInterval = 0
    let minimumRepeatDelay: TimeInterval = 0.05
    let minimumRepeatInterval: TimeInterval = 0.01

    var mouseClickedButton: Int64 = 0
    var mouseClickedAt: Double = 0

    var mouseDownState: UInt16 = 0
    var lastMousePosition: CGPoint? = nil

    init() {
        serialQueue.setSpecific(key: serialQueueKey, value: ())
    }

    func prepare() throws {
        guard let eventSource = CGEventSource(stateID: .combinedSessionState) else {
            throw EventInjectorError.initializationError
        }

        self.eventSource = eventSource
        refreshKeyRepeatSettings()
    }

    func resetKeyboardState() {
        enqueue { [weak self] in
            self?.resetKeyboardStateOnQueue()
        }
    }

    func refreshKeyRepeatSettings() {
        repeatDelay = NSEvent.keyRepeatDelay
        repeatInterval = NSEvent.keyRepeatInterval
    }

    func isRepeatEnabled() -> Bool {
        return repeatDelay >= minimumRepeatDelay && repeatInterval >= minimumRepeatInterval
    }

    func dispatchInterval(for seconds: TimeInterval) -> DispatchTimeInterval {
        let nanoseconds = Int(max(0, seconds) * 1_000_000_000)
        return .nanoseconds(nanoseconds)
    }

    func enqueue(_ block: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: serialQueueKey) != nil {
            block()
        } else {
            serialQueue.async(execute: block)
        }
    }

    func stopRepeatTimer() {
        repeatTimer?.cancel()
        repeatTimer = nil
    }

    func resetKeyboardStateOnQueue() {
        stopRepeatTimer()
        repeatKey = nil
        repeatableKeysInOrder.removeAll()

        if !keyDownState.isEmpty {
            for keyCode in keyDownState {
                postKeyEvent(keyCode: keyCode, isDown: false, isRepeat: false)
            }
            keyDownState.removeAll()
        }
    }

    func postKeyEvent(keyCode: Int, isDown: Bool, isRepeat: Bool) {
        guard let cgEvent = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: CGKeyCode(keyCode),
            keyDown: isDown
        )
        else {
            return
        }

        if isRepeat {
            cgEvent.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        }

        cgEvent.sanitizeModifierFlags(with: keyDownState)
        cgEvent.post(tap: .cgSessionEventTap)
    }
}

extension CGEvent {
    func sanitizeModifierFlags(with keyDownState: Set<Int>) {
        // HACK: 이유는 모르겠으나 fn 키가 계속 눌림
        flags.remove(.maskSecondaryFn)
        flags.remove(.maskNumericPad)
        flags.remove(.maskShift)
        flags.remove(.maskAlternate)
        flags.remove(.maskControl)
        flags.remove(.maskCommand)

        if ((keyDownState.contains(kVK_Shift) ||
              keyDownState.contains(kVK_RightShift))) {
            flags.insert(.maskShift)
        }

        if ((keyDownState.contains(kVK_Option) ||
              keyDownState.contains(kVK_RightOption))) {
            flags.insert(.maskAlternate)
        }

        if ((keyDownState.contains(kVK_Control) ||
              keyDownState.contains(kVK_RightControl))) {
            flags.insert(.maskControl)
        }

        if ((keyDownState.contains(kVK_Command) ||
              keyDownState.contains(kVK_RightCommand))) {
            flags.insert(.maskCommand)
        }
    }
}
