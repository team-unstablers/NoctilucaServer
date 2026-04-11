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

/// macOS 호스트 시스템에 키보드/마우스 이벤트를 주입한다.
///
/// # 동시성 모델
///
/// `EventInjector` 는 `actor` 로 격리되어 있지만, `unownedExecutor` 를 `serialQueue`
/// (`DispatchSerialQueue`) 에 바인딩하여 **모든 actor-isolated 호출이 해당 serial queue
/// 위에서 직접 실행**되도록 구성되어 있다. 이렇게 하면 기존의 `serialQueue.async { ... }`
/// 직렬화 semantic 을 그대로 유지하면서, 호출자는 `await`/actor hop 의 안전성 보장을
/// 받을 수 있다.
///
/// `DispatchSourceTimer.setEventHandler` 클로저 역시 같은 serial queue 위에서 실행
/// 되므로, 타이머 콜백 안에서는 `assumeIsolated { ... }` 로 actor hop 없이 isolated
/// 메서드를 호출한다 (Swift 5.9+ 표준 API). 
actor EventInjector {
    public static let MOUSE_DOWN_STATE_LEFT: UInt16 = 0b1
    public static let MOUSE_DOWN_STATE_RIGHT: UInt16 = 0b10

    // 어쩔 수 없었다. 미안하다.
    nonisolated let dispatchQueue = DispatchQueue.main

    nonisolated var unownedExecutor: UnownedSerialExecutor {
        MainActor.sharedUnownedExecutor
    }

    var eventSource: CGEventSource!

    var keyDownState = Set<Int>()
    var repeatableKeysInOrder: [Int] = []
    var repeatKey: Int? = nil
    var repeatTimer: DispatchSourceTimer? = nil
    var repeatDelay: TimeInterval = 0
    var repeatInterval: TimeInterval = 0
    let minimumRepeatDelay: TimeInterval = 0.05
    let minimumRepeatInterval: TimeInterval = 0.01

    var lastClickButton: UInt32 = 0
    var lastClickTime: TimeInterval = 0
    var clickCount: Int64 = 0

    var mouseDownState: UInt16 = 0
    var lastMousePosition: CGPoint? = nil

    init() {
        // actor + custom executor 조합이므로 별도 setup 불필요.
    }

    func prepare() throws {
        guard let eventSource = CGEventSource(stateID: .combinedSessionState) else {
            throw EventInjectorError.initializationError
        }

        self.eventSource = eventSource
        refreshKeyRepeatSettings()
    }

    func resetKeyboardState() {
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

    func stopRepeatTimer() {
        repeatTimer?.cancel()
        repeatTimer = nil
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

        var charCode: UniChar = switch keyCode {
            case kVK_Tab: 0x09 // Tab
            case kVK_LeftArrow: 0xF702 // Left
            case kVK_RightArrow: 0xF703 // Right
            case kVK_DownArrow: 0xF701 // Down
            case kVK_UpArrow: 0xF700 // Up
            default: 0
        }

        if charCode != 0 {
            cgEvent.keyboardSetUnicodeString(stringLength: 1, unicodeString: &charCode)
        }

        if isRepeat {
            cgEvent.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        }

        cgEvent.sanitizeModifierFlags(with: keyDownState)

        switch keyCode {
        case kVK_LeftArrow, kVK_RightArrow, kVK_DownArrow, kVK_UpArrow:
            // HACK: 이 플래그를 넣지 않으면 Xcode vim mode에서 방향키 네비게이션이 불가능해짐
            cgEvent.flags.insert(.maskSecondaryFn)
            cgEvent.flags.insert(.maskNumericPad)

        case kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
            kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12:
            cgEvent.flags.insert(.maskSecondaryFn)
        default:
            break
        }

        cgEvent.post(tap: .cgSessionEventTap)
    }
}

extension CGEvent {
    func sanitizeModifierFlags(with keyDownState: Set<Int>) {
        // HACK: 이유는 모르겠으나 fn 키가 계속 눌림

        flags = []
        /*
        flags.remove(.maskSecondaryFn)
        flags.remove(.maskNumericPad)
        flags.remove(.maskShift)
        flags.remove(.maskAlternate)
        flags.remove(.maskControl)
        flags.remove(.maskCommand)
         */

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
