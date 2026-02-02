//
//  Keycode.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/18/25.
//

#if canImport(Carbon)
import Foundation
import Carbon

public typealias SRCarbonKeycode = Int

public extension LinuxKeycode {
    fileprivate static let undefined = LinuxKeycode.KEY_UNKNOWN
    
    /// Carbon Keycode (Index) to Linux Keycode (Value) Mapping
    static let carbonToLinux: [LinuxKeycode] = [
        .KEY_A,                 // 0x00: kVK_ANSI_A
        .KEY_S,                 // 0x01: kVK_ANSI_S
        .KEY_D,                 // 0x02: kVK_ANSI_D
        .KEY_F,                 // 0x03: kVK_ANSI_F
        .KEY_H,                 // 0x04: kVK_ANSI_H
        .KEY_G,                 // 0x05: kVK_ANSI_G
        .KEY_Z,                 // 0x06: kVK_ANSI_Z
        .KEY_X,                 // 0x07: kVK_ANSI_X
        .KEY_C,                 // 0x08: kVK_ANSI_C
        .KEY_V,                 // 0x09: kVK_ANSI_V
        .KEY_102ND,             // 0x0A: kVK_ISO_Section (Non-US Backslash)
        .KEY_B,                 // 0x0B: kVK_ANSI_B
        .KEY_Q,                 // 0x0C: kVK_ANSI_Q
        .KEY_W,                 // 0x0D: kVK_ANSI_W
        .KEY_E,                 // 0x0E: kVK_ANSI_E
        .KEY_R,                 // 0x0F: kVK_ANSI_R
        .KEY_Y,                 // 0x10: kVK_ANSI_Y
        .KEY_T,                 // 0x11: kVK_ANSI_T
        .KEY_1,                 // 0x12: kVK_ANSI_1
        .KEY_2,                 // 0x13: kVK_ANSI_2
        .KEY_3,                 // 0x14: kVK_ANSI_3
        .KEY_4,                 // 0x15: kVK_ANSI_4
        .KEY_6,                 // 0x16: kVK_ANSI_6
        .KEY_5,                 // 0x17: kVK_ANSI_5
        .KEY_EQUAL,             // 0x18: kVK_ANSI_Equal
        .KEY_9,                 // 0x19: kVK_ANSI_9
        .KEY_7,                 // 0x1A: kVK_ANSI_7
        .KEY_MINUS,             // 0x1B: kVK_ANSI_Minus
        .KEY_8,                 // 0x1C: kVK_ANSI_8
        .KEY_0,                 // 0x1D: kVK_ANSI_0
        .KEY_RIGHTBRACE,        // 0x1E: kVK_ANSI_RightBracket
        .KEY_O,                 // 0x1F: kVK_ANSI_O
        .KEY_U,                 // 0x20: kVK_ANSI_U
        .KEY_LEFTBRACE,         // 0x21: kVK_ANSI_LeftBracket
        .KEY_I,                 // 0x22: kVK_ANSI_I
        .KEY_P,                 // 0x23: kVK_ANSI_P
        .KEY_ENTER,             // 0x24: kVK_Return
        .KEY_L,                 // 0x25: kVK_ANSI_L
        .KEY_J,                 // 0x26: kVK_ANSI_J
        .KEY_APOSTROPHE,        // 0x27: kVK_ANSI_Quote
        .KEY_K,                 // 0x28: kVK_ANSI_K
        .KEY_SEMICOLON,         // 0x29: kVK_ANSI_Semicolon
        .KEY_BACKSLASH,         // 0x2A: kVK_ANSI_Backslash
        .KEY_COMMA,             // 0x2B: kVK_ANSI_Comma
        .KEY_SLASH,             // 0x2C: kVK_ANSI_Slash
        .KEY_N,                 // 0x2D: kVK_ANSI_N
        .KEY_M,                 // 0x2E: kVK_ANSI_M
        .KEY_DOT,               // 0x2F: kVK_ANSI_Period
        .KEY_TAB,               // 0x30: kVK_Tab
        .KEY_SPACE,             // 0x31: kVK_Space
        .KEY_GRAVE,             // 0x32: kVK_ANSI_Grave
        .KEY_BACKSPACE,         // 0x33: kVK_Delete (Mac Delete is Backspace)
        .undefined,             // 0x34: kVK_ISO_Enter (Often unused or KP_ENTER)
        .KEY_ESC,               // 0x35: kVK_Escape
        .KEY_RIGHTMETA,         // 0x36: kVK_Command (Right)
        .KEY_LEFTMETA,          // 0x37: kVK_Command (Left)
        .KEY_LEFTSHIFT,         // 0x38: kVK_Shift (Left)
        .KEY_CAPSLOCK,          // 0x39: kVK_CapsLock
        .KEY_LEFTALT,           // 0x3A: kVK_Option (Left)
        .KEY_LEFTCTRL,          // 0x3B: kVK_Control (Left)
        .KEY_RIGHTSHIFT,        // 0x3C: kVK_Shift (Right)
        .KEY_RIGHTALT,          // 0x3D: kVK_Option (Right)
        .KEY_RIGHTCTRL,         // 0x3E: kVK_Control (Right)
        .undefined,             // 0x3F: kVK_Function (Hardware Fn key, rarely sends code)
        .KEY_F17,               // 0x40: kVK_F17
        .KEY_KPDOT,             // 0x41: kVK_ANSI_KeypadDecimal
        .undefined,             // 0x42: Unused
        .KEY_KPASTERISK,        // 0x43: kVK_ANSI_KeypadMultiply
        .undefined,             // 0x44: Unused
        .KEY_KPPLUS,            // 0x45: kVK_ANSI_KeypadPlus
        .undefined,             // 0x46: Unused
        .KEY_NUMLOCK,           // 0x47: kVK_ANSI_KeypadClear (Often maps to NumLock)
        .KEY_VOLUMEUP,          // 0x48: kVK_VolumeUp
        .KEY_VOLUMEDOWN,        // 0x49: kVK_VolumeDown
        .KEY_MUTE,              // 0x4A: kVK_Mute
        .KEY_KPSLASH,           // 0x4B: kVK_ANSI_KeypadDivide
        .KEY_KPENTER,           // 0x4C: kVK_ANSI_KeypadEnter
        .undefined,             // 0x4D: Unused
        .KEY_KPMINUS,           // 0x4E: kVK_ANSI_KeypadMinus
        .KEY_F18,               // 0x4F: kVK_F18
        .KEY_F19,               // 0x50: kVK_F19
        .KEY_KPEQUAL,           // 0x51: kVK_ANSI_KeypadEquals
        .KEY_KP0,               // 0x52: kVK_ANSI_Keypad0
        .KEY_KP1,               // 0x53: kVK_ANSI_Keypad1
        .KEY_KP2,               // 0x54: kVK_ANSI_Keypad2
        .KEY_KP3,               // 0x55: kVK_ANSI_Keypad3
        .KEY_KP4,               // 0x56: kVK_ANSI_Keypad4
        .KEY_KP5,               // 0x57: kVK_ANSI_Keypad5
        .KEY_KP6,               // 0x58: kVK_ANSI_Keypad6
        .KEY_KP7,               // 0x59: kVK_ANSI_Keypad7
        .KEY_F20,               // 0x5A: kVK_F20
        .KEY_KP8,               // 0x5B: kVK_ANSI_Keypad8
        .KEY_KP9,               // 0x5C: kVK_ANSI_Keypad9
        .KEY_YEN,               // 0x5D: kVK_JIS_Yen
        .KEY_RO,                // 0x5E: kVK_JIS_Underscore
        .KEY_KPJPCOMMA,         // 0x5F: kVK_JIS_KeypadComma
        .KEY_F5,                // 0x60: kVK_F5
        .KEY_F6,                // 0x61: kVK_F6
        .KEY_F7,                // 0x62: kVK_F7
        .KEY_F3,                // 0x63: kVK_F3
        .KEY_F8,                // 0x64: kVK_F8
        .KEY_F9,                // 0x65: kVK_F9
        .KEY_MUHENKAN,          // 0x66: kVK_JIS_Eisu
        .KEY_F11,               // 0x67: kVK_F11
        .KEY_KATAKANAHIRAGANA,  // 0x68: kVK_JIS_Kana
        .KEY_F13,               // 0x69: kVK_F13
        .KEY_F16,               // 0x6A: kVK_F16
        .KEY_F14,               // 0x6B: kVK_F14
        .undefined,             // 0x6C: Unused
        .KEY_F10,               // 0x6D: kVK_F10
        .KEY_MENU,              // 0x6E: kVK_ContextualMenu
        .KEY_F12,               // 0x6F: kVK_F12
        .undefined,             // 0x70: Unused
        .KEY_F15,               // 0x71: kVK_F15
        .KEY_HELP,              // 0x72: kVK_Help
        .KEY_HOME,              // 0x73: kVK_Home
        .KEY_PAGEUP,            // 0x74: kVK_PageUp
        .KEY_DELETE,            // 0x75: kVK_ForwardDelete (Mac Fn+Delete is Del)
        .KEY_F4,                // 0x76: kVK_F4
        .KEY_END,               // 0x77: kVK_End
        .KEY_F2,                // 0x78: kVK_F2
        .KEY_PAGEDOWN,          // 0x79: kVK_PageDown
        .KEY_F1,                // 0x7A: kVK_F1
        .KEY_LEFT,              // 0x7B: kVK_LeftArrow
        .KEY_RIGHT,             // 0x7C: kVK_RightArrow
        .KEY_DOWN,              // 0x7D: kVK_DownArrow
        .KEY_UP,                // 0x7E: kVK_UpArrow
    ]
    
    /// Linux Keycode to Carbon Keycode Dictionary
    /// `carbonToLinux` 배열을 기반으로 런타임에 한 번 생성됩니다. (Lazy Initialization)
    static let linuxToCarbon: [LinuxKeycode: SRCarbonKeycode] = {
        var mapping: [LinuxKeycode: SRCarbonKeycode] = [:]
        
        for (carbonIndex, linuxKey) in carbonToLinux.enumerated() {
            // UNKNOWN 키는 매핑하지 않습니다.
            guard linuxKey != .KEY_UNKNOWN else { continue }
            
            // 딕셔너리에 [LinuxKey: CarbonCode] 형태로 저장
            // 만약 하나의 Linux 키에 여러 Carbon 코드가 매핑되어 있다면,
            // 나중에 나온(Index가 큰) Carbon 코드로 덮어씌워집니다.
            mapping[linuxKey] = SRCarbonKeycode(carbonIndex)
        }
        
        return mapping
    }()
    
    static func from(carbon keycode: SRCarbonKeycode) -> LinuxKeycode {
        if keycode >= carbonToLinux.count {
            return .KEY_UNKNOWN
        }
        
        return carbonToLinux[keycode]
    }
    
    var toCarbonKeycode: SRCarbonKeycode? {
        return Self.linuxToCarbon[self]
    }
}

#endif
