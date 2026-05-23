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
        /// 독점 모드 ↔ 공유 모드를 토글하는 단축키.
        /// 호환성: 0.9.x 이전 빌드에서는 `unlockKeySequence` 라는 이름으로 직렬화되었으며,
        /// decode 시 구 키도 fallback 으로 처리한다.
        var toggleExclusiveModeKeySequence: KeySequence = KeySequence(modifier: [.KEY_LEFTALT], key: .KEY_ESC)
        var redirectionMethod: InputRedirectionMethod = .gameController
        var modifierKeyOverrides: ModifierKeyOverrides = .init()
        
#if os(macOS)
        var syncIMState: Bool = true
        var syncIMStatePreferThirdParty: Bool = false
#endif
        
#if os(macOS)
        var redirectKnownShortcuts: Bool = false
#endif
        
        
#if os(iOS)
        var enableGCMouse: Bool = true
#endif
        var pointerInputMode: PointerInputMode = .automatic
        var touchInputMode: TouchInputMode = .trackpad
        var trackpadMoveMultiplier: Double = 1.0
        var cursorScale: Double = 1.0
        var invertMouseButtons: Bool = false
        var invertVerticalScroll: Bool = false
        var invertHorizontalScroll: Bool = false
        var mouseScrollMultiplier: Double = 1.0
#if os(macOS)
        var mouseAccelerationMode: MouseAccelerationMode = .adaptive
        var mouseAccelerationSensitivity: Double = -0.3
#endif

        init() {}

        enum CodingKeys: String, CodingKey {
            case enableExclusiveMode
            case toggleExclusiveModeKeySequence
            /// 0.9.x 이전 직렬화 호환용. decode 전용으로만 사용한다.
            case unlockKeySequence
            case redirectionMethod
            case modifierKeyOverrides
#if os(macOS)
            case syncIMState
            case syncIMStatePreferThirdParty
#endif
#if os(macOS)
            case redirectKnownShortcuts
#endif
#if os(iOS)
            case enableGCMouse
#endif
            case pointerInputMode
            case touchInputMode
            case trackpadMoveMultiplier
            case cursorScale
            case invertMouseButtons
            case invertVerticalScroll
            case invertHorizontalScroll
            case mouseScrollMultiplier
#if os(macOS)
            case mouseAccelerationMode
            case mouseAccelerationSensitivity
#endif
        }

        init(from decoder: any Decoder) throws {
            self.init()

            guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                return
            }
            
            enableExclusiveMode = container.decodeSafe(Bool.self, forKey: .enableExclusiveMode, default: true)
            // 새 키가 있으면 그것을 사용하고, 없으면 0.9.x 이전 구 키 (`unlockKeySequence`) 를 fallback 으로 읽는다.
            if container.contains(.toggleExclusiveModeKeySequence) {
                toggleExclusiveModeKeySequence = container.decodeSafe(
                    KeySequence.self,
                    forKey: .toggleExclusiveModeKeySequence,
                    default: toggleExclusiveModeKeySequence
                )
            } else {
                toggleExclusiveModeKeySequence = container.decodeSafe(
                    KeySequence.self,
                    forKey: .unlockKeySequence,
                    default: toggleExclusiveModeKeySequence
                )
            }
            redirectionMethod = container.decodeSafe(InputRedirectionMethod.self, forKey: .redirectionMethod, default: redirectionMethod)
            modifierKeyOverrides = container.decodeSafe(ModifierKeyOverrides.self, forKey: .modifierKeyOverrides, default: modifierKeyOverrides)
            
#if os(macOS)
            syncIMState = container.decodeSafe(Bool.self, forKey: .syncIMState, default: syncIMState)
            syncIMStatePreferThirdParty = container.decodeSafe(Bool.self, forKey: .syncIMStatePreferThirdParty, default: syncIMStatePreferThirdParty)
#endif
            
#if os(macOS)
            redirectKnownShortcuts = container.decodeSafe(Bool.self, forKey: .redirectKnownShortcuts, default: redirectKnownShortcuts)
#endif
#if os(iOS)
            enableGCMouse = container.decodeSafe(Bool.self, forKey: .enableGCMouse, default: enableGCMouse)
#endif
            pointerInputMode = container.decodeSafe(PointerInputMode.self, forKey: .pointerInputMode, default: pointerInputMode)
            touchInputMode = container.decodeSafe(TouchInputMode.self, forKey: .touchInputMode, default: touchInputMode)
            trackpadMoveMultiplier = container.decodeSafe(Double.self, forKey: .trackpadMoveMultiplier, default: trackpadMoveMultiplier)
            cursorScale = container.decodeSafe(Double.self, forKey: .cursorScale, default: cursorScale)
            invertMouseButtons = container.decodeSafe(Bool.self, forKey: .invertMouseButtons, default: invertMouseButtons)
            invertVerticalScroll = container.decodeSafe(Bool.self, forKey: .invertVerticalScroll, default: invertVerticalScroll)
            invertHorizontalScroll = container.decodeSafe(Bool.self, forKey: .invertHorizontalScroll, default: invertHorizontalScroll)
            mouseScrollMultiplier = container.decodeSafe(Double.self, forKey: .mouseScrollMultiplier, default: mouseScrollMultiplier)
#if os(macOS)
            mouseAccelerationMode = container.decodeSafe(MouseAccelerationMode.self, forKey: .mouseAccelerationMode, default: mouseAccelerationMode)
            mouseAccelerationSensitivity = container.decodeSafe(Double.self, forKey: .mouseAccelerationSensitivity, default: mouseAccelerationSensitivity)
#endif
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(enableExclusiveMode, forKey: .enableExclusiveMode)
            try container.encode(toggleExclusiveModeKeySequence, forKey: .toggleExclusiveModeKeySequence)
            try container.encode(redirectionMethod, forKey: .redirectionMethod)
            try container.encode(modifierKeyOverrides, forKey: .modifierKeyOverrides)
#if os(macOS)
            try container.encode(syncIMState, forKey: .syncIMState)
            try container.encode(syncIMStatePreferThirdParty, forKey: .syncIMStatePreferThirdParty)
#endif
            
#if os(macOS)
            try container.encode(redirectKnownShortcuts, forKey: .redirectKnownShortcuts)
#endif
#if os(iOS)
            try container.encode(enableGCMouse, forKey: .enableGCMouse)
#endif
            try container.encode(pointerInputMode, forKey: .pointerInputMode)
            try container.encode(touchInputMode, forKey: .touchInputMode)
            try container.encode(trackpadMoveMultiplier, forKey: .trackpadMoveMultiplier)
            try container.encode(cursorScale, forKey: .cursorScale)
            try container.encode(invertMouseButtons, forKey: .invertMouseButtons)
            try container.encode(invertVerticalScroll, forKey: .invertVerticalScroll)
            try container.encode(invertHorizontalScroll, forKey: .invertHorizontalScroll)
            try container.encode(mouseScrollMultiplier, forKey: .mouseScrollMultiplier)
#if os(macOS)
            try container.encode(mouseAccelerationMode, forKey: .mouseAccelerationMode)
            try container.encode(mouseAccelerationSensitivity, forKey: .mouseAccelerationSensitivity)
#endif
        }
    }
}
