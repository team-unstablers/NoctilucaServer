//
//  KeyEventRebinder.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/12/26.
//

import Foundation

import SiriusKitClient

class KeyEventRebinder: KeyEventPipeline {
    // nil value = disabled (이벤트 삭제)
    // key 없음 = 패스스루
    private var bindings: [LinuxKeycode: LinuxKeycode?] = [:]

    func register(from source: LinuxKeycode, to target: LinuxKeycode?) {
        bindings[source] = target
    }

    func unregister(from source: LinuxKeycode) {
        bindings.removeValue(forKey: source)
    }

    func unregisterAll() {
        bindings.removeAll()
    }

    func process(_ keyEvent: KeyboardEvent) -> KeyboardEvent? {
        let keyCode = LinuxKeycode(rawValue: UInt16(keyEvent.keyCode))

        guard let binding = bindings[keyCode] else {
            // 미등록: 패스스루
            return keyEvent
        }

        guard let targetKeyCode = binding else {
            // disabled: 이벤트 삭제
            return nil
        }

        return KeyboardEvent(
            eventType: keyEvent.eventType,
            scanCode: keyEvent.scanCode,
            keyCode: UInt32(targetKeyCode.rawValue),
            modifiers: keyEvent.modifiers,
            flags: keyEvent.flags
        )
    }
}
