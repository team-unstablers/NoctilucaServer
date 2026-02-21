//
//  HIDIOUIKitKeyboard.swift
//  NoctilucaClient
//
//  Created by Codex on 12/31/25.
//

#if os(iOS)

import Foundation
import Combine

import SiriusKitClient

extension HIDIOVirtualDeviceIdentifier {
    /// UIKit on-screen keyboard 기반 가상 키보드 디바이스 (iOS 전용).
    static let uiKitKeyboard = Self(rawValue: UUID(uuidString: "7C3A0B9A-0A9C-4A0C-9B43-5F1C4E1C6A51")!)
}

final class HIDIOUIKitKeyboard: ObservableObject, HIDIOVirtualDevice {
    static let kind: HIDIOVirtualDeviceKind = .keyboard
    static let identifier: HIDIOVirtualDeviceIdentifier = .uiKitKeyboard

    @Published
    private(set) var activeModifiers: Set<LinuxKeycode> = []

    private weak var controller: HIDIOController?

    func connect(to controller: HIDIOController) {
        self.controller = controller
    }

    func disconnect() {
        resetModifiers()
        controller = nil
    }

    func isModifierActive(_ keyCode: LinuxKeycode) -> Bool {
        activeModifiers.contains(keyCode)
    }

    func toggleModifier(_ keyCode: LinuxKeycode) {
        let shouldEnable = !activeModifiers.contains(keyCode)
        setModifier(keyCode, enabled: shouldEnable)
    }

    func setModifier(_ keyCode: LinuxKeycode, enabled: Bool) {
        guard let controller else {
            return
        }

        if enabled {
            guard !activeModifiers.contains(keyCode) else {
                return
            }

            controller.keyDown(keyCode: keyCode)
            activeModifiers.insert(keyCode)
        } else {
            guard activeModifiers.contains(keyCode) else {
                return
            }

            controller.keyUp(keyCode: keyCode)
            activeModifiers.remove(keyCode)
        }
    }

    func resetModifiers() {
        guard let controller else {
            activeModifiers = []
            return
        }

        for keyCode in activeModifiers {
            controller.keyUp(keyCode: keyCode)
        }

        activeModifiers = []
    }

    func keyDown(_ keyCode: LinuxKeycode) {
        controller?.keyDown(keyCode: keyCode)
    }

    func keyUp(_ keyCode: LinuxKeycode) {
        controller?.keyUp(keyCode: keyCode)
    }

    func sendKey(_ keyCode: LinuxKeycode) {
        guard let controller else {
            return
        }

        controller.keyDown(keyCode: keyCode)
        controller.keyUp(keyCode: keyCode)
    }

    func handleDeleteBackward() {
        sendKey(.KEY_BACKSPACE)
    }
    
    func handleReturnKey() {
        sendKey(.KEY_ENTER)
    }

    func handleInsertText(_ text: String) {
        for character in text {
            if let mapped = HIDIOUIKitKeyboardKeyMapper.map(character: character) {
                sendMappedKey(mapped)
            } else {
                sendUCS4(character)
            }
        }
    }

    /// keycode 매핑이 불가능한 문자를 UCS4 코드포인트로 직접 전송합니다.
    private func sendUCS4(_ character: Character) {
        guard let controller else {
            return
        }

        for scalar in character.unicodeScalars {
            controller.sendUCS4(scalar.value)
        }
    }

    func sendMappedKey(_ mapped: HIDIOUIKitKeyboardKeyMapper.MappedKey) {
        guard let controller else {
            return
        }

        let needsTemporaryShift = mapped.requiresShift && !activeModifiers.contains(.KEY_LEFTSHIFT)

        if needsTemporaryShift {
            controller.keyDown(keyCode: .KEY_LEFTSHIFT)
        }

        controller.keyDown(keyCode: mapped.keyCode)
        controller.keyUp(keyCode: mapped.keyCode)

        if needsTemporaryShift {
            controller.keyUp(keyCode: .KEY_LEFTSHIFT)
        }
    }
}

enum HIDIOUIKitKeyboardKeyMapper {
    struct MappedKey {
        let keyCode: LinuxKeycode
        let requiresShift: Bool
    }

    static func map(character: Character) -> MappedKey? {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
            return nil
        }

        let value = scalar.value

        if value >= 65 && value <= 90 {
            guard let lowerScalar = UnicodeScalar(value + 32) else {
                return nil
            }
            let lowerChar = Character(lowerScalar)
            if let mapped = mapUnshifted(character: lowerChar) {
                return MappedKey(keyCode: mapped.keyCode, requiresShift: true)
            }
            return nil
        }

        if let mapped = shiftedPunctuationMapping[character] {
            return MappedKey(keyCode: mapped, requiresShift: true)
        }

        return mapUnshifted(character: character)
    }

    private static func mapUnshifted(character: Character) -> MappedKey? {
        if let mapped = letterMapping[character] {
            return MappedKey(keyCode: mapped, requiresShift: false)
        }

        if let mapped = digitMapping[character] {
            return MappedKey(keyCode: mapped, requiresShift: false)
        }

        if let mapped = punctuationMapping[character] {
            return MappedKey(keyCode: mapped, requiresShift: false)
        }

        if character == "\n" || character == "\r" {
            return MappedKey(keyCode: .KEY_ENTER, requiresShift: false)
        }

        if character == "\t" {
            return MappedKey(keyCode: .KEY_TAB, requiresShift: false)
        }

        return nil
    }

    private static let letterMapping: [Character: LinuxKeycode] = [
        "a": .KEY_A,
        "b": .KEY_B,
        "c": .KEY_C,
        "d": .KEY_D,
        "e": .KEY_E,
        "f": .KEY_F,
        "g": .KEY_G,
        "h": .KEY_H,
        "i": .KEY_I,
        "j": .KEY_J,
        "k": .KEY_K,
        "l": .KEY_L,
        "m": .KEY_M,
        "n": .KEY_N,
        "o": .KEY_O,
        "p": .KEY_P,
        "q": .KEY_Q,
        "r": .KEY_R,
        "s": .KEY_S,
        "t": .KEY_T,
        "u": .KEY_U,
        "v": .KEY_V,
        "w": .KEY_W,
        "x": .KEY_X,
        "y": .KEY_Y,
        "z": .KEY_Z
    ]

    private static let digitMapping: [Character: LinuxKeycode] = [
        "0": .KEY_0,
        "1": .KEY_1,
        "2": .KEY_2,
        "3": .KEY_3,
        "4": .KEY_4,
        "5": .KEY_5,
        "6": .KEY_6,
        "7": .KEY_7,
        "8": .KEY_8,
        "9": .KEY_9
    ]

    private static let punctuationMapping: [Character: LinuxKeycode] = [
        " ": .KEY_SPACE,
        "-": .KEY_MINUS,
        "=": .KEY_EQUAL,
        "[": .KEY_LEFTBRACE,
        "]": .KEY_RIGHTBRACE,
        "\\": .KEY_BACKSLASH,
        ";": .KEY_SEMICOLON,
        "'": .KEY_APOSTROPHE,
        ",": .KEY_COMMA,
        ".": .KEY_DOT,
        "/": .KEY_SLASH,
        "`": .KEY_GRAVE
    ]

    private static let shiftedPunctuationMapping: [Character: LinuxKeycode] = [
        "!": .KEY_1,
        "@": .KEY_2,
        "#": .KEY_3,
        "$": .KEY_4,
        "%": .KEY_5,
        "^": .KEY_6,
        "&": .KEY_7,
        "*": .KEY_8,
        "(": .KEY_9,
        ")": .KEY_0,
        "_": .KEY_MINUS,
        "+": .KEY_EQUAL,
        "{": .KEY_LEFTBRACE,
        "}": .KEY_RIGHTBRACE,
        "|": .KEY_BACKSLASH,
        ":": .KEY_SEMICOLON,
        "\"": .KEY_APOSTROPHE,
        "<": .KEY_COMMA,
        ">": .KEY_DOT,
        "?": .KEY_SLASH,
        "~": .KEY_GRAVE
    ]
}

#endif
