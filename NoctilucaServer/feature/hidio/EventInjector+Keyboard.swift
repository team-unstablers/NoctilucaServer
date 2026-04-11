//
//  EventInjector+Keyboard.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/11/25.
//

import Foundation

import Carbon
import CoreGraphics

import SiriusKit

extension EventInjector {
    func postKeyDown(_ keyCode: Int) {
        handleKeyDown(keyCode)
    }

    func postKeyUp(_ keyCode: Int) {
        handleKeyUp(keyCode)
    }

    func postUcs4Input(_ ucs4: UInt32) {
        guard let scalar = UnicodeScalar(ucs4) else { return }
        let utf16Chars = Array(String(scalar).utf16)

        // UCS4 입력은 keyDown/keyUp을 원샷으로 발생시켜 문자를 주입합니다.
        // virtualKey 0(A)은 UnicodeString이 설정되면 무시됩니다.
        if let downEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: true) {
            downEvent.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
            downEvent.post(tap: .cgSessionEventTap)
        }

        if let upEvent = CGEvent(keyboardEventSource: eventSource, virtualKey: 0, keyDown: false) {
            upEvent.keyboardSetUnicodeString(stringLength: utf16Chars.count, unicodeString: utf16Chars)
            upEvent.post(tap: .cgSessionEventTap)
        }
    }

    func handleKeyDown(_ keyCode: Int) {
        if keyDownState.contains(keyCode) {
            return
        }

        keyDownState.insert(keyCode)
        postKeyEvent(keyCode: keyCode, isDown: true, isRepeat: false)

        guard isRepeatableKey(keyCode) else {
            return
        }

        repeatableKeysInOrder.removeAll(where: { $0 == keyCode })
        repeatableKeysInOrder.append(keyCode)
        repeatKey = keyCode
        refreshKeyRepeatSettings()
        restartRepeatTimerIfNeeded()
    }

    func handleKeyUp(_ keyCode: Int) {
        let wasDown = keyDownState.contains(keyCode)
        if wasDown {
            keyDownState.remove(keyCode)
        }

        postKeyEvent(keyCode: keyCode, isDown: false, isRepeat: false)

        guard isRepeatableKey(keyCode) else {
            return
        }

        repeatableKeysInOrder.removeAll(where: { $0 == keyCode })

        if repeatKey == keyCode {
            if let nextKey = repeatableKeysInOrder.last {
                repeatKey = nextKey
                refreshKeyRepeatSettings()
                restartRepeatTimerIfNeeded()
            } else {
                repeatKey = nil
                stopRepeatTimer()
            }
        }
    }

    func restartRepeatTimerIfNeeded() {
        stopRepeatTimer()

        guard isRepeatEnabled(), let repeatKey = repeatKey, keyDownState.contains(repeatKey) else {
            return
        }

        let timer = DispatchSource.makeTimerSource(queue: dispatchQueue)
        let delay = dispatchInterval(for: repeatDelay)
        let interval = dispatchInterval(for: repeatInterval)

        timer.schedule(deadline: .now() + delay, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            // 타이머는 serialQueue(= actor 의 unowned executor) 위에서 실행되므로
            // actor-isolated 메서드를 hop 없이 직접 호출할 수 있다.
            self.assumeIsolated { me in
                me.handleRepeatTick()
            }
        }
        timer.resume()

        repeatTimer = timer
    }

    func handleRepeatTick() {
        guard let repeatKey = repeatKey,
              keyDownState.contains(repeatKey),
              isRepeatEnabled()
        else {
            stopRepeatTimer()
            return
        }

        postKeyEvent(keyCode: repeatKey, isDown: true, isRepeat: true)
    }

    func isRepeatableKey(_ keyCode: Int) -> Bool {
        switch keyCode {
        case kVK_Shift,
             kVK_RightShift,
             kVK_Control,
             kVK_RightControl,
             kVK_Option,
             kVK_RightOption,
             kVK_Command,
             kVK_RightCommand,
             kVK_Function,
             kVK_CapsLock:
            return false
        default:
            return true
        }
    }
}
