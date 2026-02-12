//
//  InputSettings.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

import SiriusKitClient

extension AppSettings {
    enum InputRedirectionMethod: String, Codable, CaseIterable, Sendable {
        case gameController
        case cocoaEventTap

        init(from decoder: any Decoder) throws {
            let container = try? decoder.singleValueContainer()
            let rawValue = (try? container?.decode(String.self)) ?? Self.gameController.rawValue
            self = InputRedirectionMethod(rawValue: rawValue) ?? .gameController
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    enum ModifierKeyOverride: String, Codable, CaseIterable, Sendable {
        case capsLock
        case control
        case option
        case command
        case escape
        case disabled

        init(from decoder: any Decoder) throws {
            let container = try? decoder.singleValueContainer()
            let rawValue = (try? container?.decode(String.self)) ?? Self.disabled.rawValue
            self = ModifierKeyOverride(rawValue: rawValue) ?? .disabled
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    enum MouseMoveMode: String, Codable, CaseIterable, Sendable {
        case absolute
        case relative

        init(from decoder: any Decoder) throws {
            let container = try? decoder.singleValueContainer()
            let rawValue = (try? container?.decode(String.self)) ?? Self.absolute.rawValue
            self = MouseMoveMode(rawValue: rawValue) ?? .absolute
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    enum PointerInputMode: String, Codable, CaseIterable, Sendable {
        case automatic
        case touchPointer
        case hardwareMouse

        init(from decoder: any Decoder) throws {
            let container = try? decoder.singleValueContainer()
            let rawValue = (try? container?.decode(String.self)) ?? Self.automatic.rawValue
            self = PointerInputMode(rawValue: rawValue) ?? .automatic
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    enum TouchInputMode: String, Codable, CaseIterable, Sendable {
        case touch
        case trackpad

        init(from decoder: any Decoder) throws {
            let container = try? decoder.singleValueContainer()
            let rawValue = (try? container?.decode(String.self)) ?? Self.touch.rawValue
            self = TouchInputMode(rawValue: rawValue) ?? .touch
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    struct ModifierKeyOverrides: Codable, Sendable, Equatable {
        var capsLock: ModifierKeyOverride = .capsLock
        var control: ModifierKeyOverride = .control
        var option: ModifierKeyOverride = .option
        var command: ModifierKeyOverride = .command

        init() {}

        enum CodingKeys: String, CodingKey {
            case capsLock
            case control
            case option
            case command
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }

            capsLock = container.decodeSafe(ModifierKeyOverride.self, forKey: .capsLock, default: capsLock)
            control = container.decodeSafe(ModifierKeyOverride.self, forKey: .control, default: control)
            option = container.decodeSafe(ModifierKeyOverride.self, forKey: .option, default: option)
            command = container.decodeSafe(ModifierKeyOverride.self, forKey: .command, default: command)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(capsLock, forKey: .capsLock)
            try container.encode(control, forKey: .control)
            try container.encode(option, forKey: .option)
            try container.encode(command, forKey: .command)
        }
    }

    struct Input: Category {
        var enableExclusiveMode: Bool = true
        var unlockKeySequence: KeySequence = KeySequence(modifier: [.KEY_LEFTALT], key: .KEY_ESC)
        var redirectionMethod: InputRedirectionMethod = .gameController
        var modifierKeyOverrides: ModifierKeyOverrides = .init()
        var mouseMoveMode: MouseMoveMode = .absolute
        var pointerInputMode: PointerInputMode = .automatic
        var touchInputMode: TouchInputMode = .touch
        var trackpadMoveMultiplier: Double = 1.0
        var invertMouseButtons: Bool = false
        var invertVerticalScroll: Bool = false
        var invertHorizontalScroll: Bool = false
        var mouseScrollMultiplier: Double = 1.0

        init() {}

        enum CodingKeys: String, CodingKey {
            case enableExclusiveMode
            case unlockKeySequence
            case redirectionMethod
            case modifierKeyOverrides
            case mouseMoveMode
            case pointerInputMode
            case touchInputMode
            case trackpadMoveMultiplier
            case invertMouseButtons
            case invertVerticalScroll
            case invertHorizontalScroll
            case mouseScrollMultiplier
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }
            
            enableExclusiveMode = container.decodeSafe(Bool.self, forKey: .enableExclusiveMode, default: true)
            unlockKeySequence = container.decodeSafe(KeySequence.self, forKey: .unlockKeySequence, default: unlockKeySequence)
            redirectionMethod = container.decodeSafe(InputRedirectionMethod.self, forKey: .redirectionMethod, default: redirectionMethod)
            modifierKeyOverrides = container.decodeSafe(ModifierKeyOverrides.self, forKey: .modifierKeyOverrides, default: modifierKeyOverrides)
            mouseMoveMode = container.decodeSafe(MouseMoveMode.self, forKey: .mouseMoveMode, default: mouseMoveMode)
            let hasPointerInputMode = container.contains(.pointerInputMode)
            pointerInputMode = container.decodeSafe(PointerInputMode.self, forKey: .pointerInputMode, default: pointerInputMode)
            touchInputMode = container.decodeSafe(TouchInputMode.self, forKey: .touchInputMode, default: touchInputMode)
            trackpadMoveMultiplier = container.decodeSafe(Double.self, forKey: .trackpadMoveMultiplier, default: trackpadMoveMultiplier)

            if !hasPointerInputMode {
                switch mouseMoveMode {
                case .relative:
                    pointerInputMode = .hardwareMouse
                case .absolute:
                    pointerInputMode = .touchPointer
                }
            }
            invertMouseButtons = container.decodeSafe(Bool.self, forKey: .invertMouseButtons, default: invertMouseButtons)
            invertVerticalScroll = container.decodeSafe(Bool.self, forKey: .invertVerticalScroll, default: invertVerticalScroll)
            invertHorizontalScroll = container.decodeSafe(Bool.self, forKey: .invertHorizontalScroll, default: invertHorizontalScroll)
            mouseScrollMultiplier = container.decodeSafe(Double.self, forKey: .mouseScrollMultiplier, default: mouseScrollMultiplier)
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(enableExclusiveMode, forKey: .enableExclusiveMode)
            try container.encode(unlockKeySequence, forKey: .unlockKeySequence)
            try container.encode(redirectionMethod, forKey: .redirectionMethod)
            try container.encode(modifierKeyOverrides, forKey: .modifierKeyOverrides)
            try container.encode(mouseMoveMode, forKey: .mouseMoveMode)
            try container.encode(pointerInputMode, forKey: .pointerInputMode)
            try container.encode(touchInputMode, forKey: .touchInputMode)
            try container.encode(trackpadMoveMultiplier, forKey: .trackpadMoveMultiplier)
            try container.encode(invertMouseButtons, forKey: .invertMouseButtons)
            try container.encode(invertVerticalScroll, forKey: .invertVerticalScroll)
            try container.encode(invertHorizontalScroll, forKey: .invertHorizontalScroll)
            try container.encode(mouseScrollMultiplier, forKey: .mouseScrollMultiplier)
        }
    }
}
