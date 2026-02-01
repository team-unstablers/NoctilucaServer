//
//  LinuxKeycode+GameController.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/18/25.
//

import SiriusKitClient
import GameController


public extension LinuxKeycode {
    /// GameController GCKeyCode to Linux Keycode Mapping
    static let gcToLinux: [GCKeyCode: LinuxKeycode] = [
        // MARK: - Letters
        .keyA: .KEY_A,
        .keyB: .KEY_B,
        .keyC: .KEY_C,
        .keyD: .KEY_D,
        .keyE: .KEY_E,
        .keyF: .KEY_F,
        .keyG: .KEY_G,
        .keyH: .KEY_H,
        .keyI: .KEY_I,
        .keyJ: .KEY_J,
        .keyK: .KEY_K,
        .keyL: .KEY_L,
        .keyM: .KEY_M,
        .keyN: .KEY_N,
        .keyO: .KEY_O,
        .keyP: .KEY_P,
        .keyQ: .KEY_Q,
        .keyR: .KEY_R,
        .keyS: .KEY_S,
        .keyT: .KEY_T,
        .keyU: .KEY_U,
        .keyV: .KEY_V,
        .keyW: .KEY_W,
        .keyX: .KEY_X,
        .keyY: .KEY_Y,
        .keyZ: .KEY_Z,
        
        // MARK: - Numbers
        .one: .KEY_1,
        .two: .KEY_2,
        .three: .KEY_3,
        .four: .KEY_4,
        .five: .KEY_5,
        .six: .KEY_6,
        .seven: .KEY_7,
        .eight: .KEY_8,
        .nine: .KEY_9,
        .zero: .KEY_0,
        
        // MARK: - Standard Command & Control
        .returnOrEnter: .KEY_ENTER,
        .escape: .KEY_ESC,
        .deleteOrBackspace: .KEY_BACKSPACE, // Backspace key
        .tab: .KEY_TAB,
        .spacebar: .KEY_SPACE,
        .capsLock: .KEY_CAPSLOCK,
        
        // MARK: - Modifiers
        .leftControl: .KEY_LEFTCTRL,
        .leftShift: .KEY_LEFTSHIFT,
        .leftAlt: .KEY_LEFTALT,
        .leftGUI: .KEY_LEFTMETA,        // Command / Windows
        .rightControl: .KEY_RIGHTCTRL,
        .rightShift: .KEY_RIGHTSHIFT,
        .rightAlt: .KEY_RIGHTALT,
        .rightGUI: .KEY_RIGHTMETA,
        
        // MARK: - Punctuation
        .hyphen: .KEY_MINUS,
        .equalSign: .KEY_EQUAL,
        .openBracket: .KEY_LEFTBRACE,
        .closeBracket: .KEY_RIGHTBRACE,
        .backslash: .KEY_BACKSLASH,
        .semicolon: .KEY_SEMICOLON,
        .quote: .KEY_APOSTROPHE,
        .graveAccentAndTilde: .KEY_GRAVE,
        .comma: .KEY_COMMA,
        .period: .KEY_DOT,
        .slash: .KEY_SLASH,
        
        // MARK: - Function Keys
        .F1: .KEY_F1,
        .F2: .KEY_F2,
        .F3: .KEY_F3,
        .F4: .KEY_F4,
        .F5: .KEY_F5,
        .F6: .KEY_F6,
        .F7: .KEY_F7,
        .F8: .KEY_F8,
        .F9: .KEY_F9,
        .F10: .KEY_F10,
        .F11: .KEY_F11,
        .F12: .KEY_F12,
        .F13: .KEY_F13,
        .F14: .KEY_F14,
        .F15: .KEY_F15,
        .F16: .KEY_F16,
        .F17: .KEY_F17,
        .F18: .KEY_F18,
        .F19: .KEY_F19,
        .F20: .KEY_F20,
        
        // MARK: - Navigation & Editing
        .printScreen: .KEY_SYSRQ,       // Often acts as SysReq/PrintScreen
        .scrollLock: .KEY_SCROLLLOCK,
        .pause: .KEY_PAUSE,
        .insert: .KEY_INSERT,
        .home: .KEY_HOME,
        .pageUp: .KEY_PAGEUP,
        .deleteForward: .KEY_DELETE,    // The dedicated 'Del' key
        .end: .KEY_END,
        .pageDown: .KEY_PAGEDOWN,
        
        // MARK: - Arrows
        .rightArrow: .KEY_RIGHT,
        .leftArrow: .KEY_LEFT,
        .downArrow: .KEY_DOWN,
        .upArrow: .KEY_UP,
        
        // MARK: - Keypad
        .keypadNumLock: .KEY_NUMLOCK,
        .keypadSlash: .KEY_KPSLASH,
        .keypadAsterisk: .KEY_KPASTERISK,
        .keypadHyphen: .KEY_KPMINUS,
        .keypadPlus: .KEY_KPPLUS,
        .keypadEnter: .KEY_KPENTER,
        .keypad1: .KEY_KP1,
        .keypad2: .KEY_KP2,
        .keypad3: .KEY_KP3,
        .keypad4: .KEY_KP4,
        .keypad5: .KEY_KP5,
        .keypad6: .KEY_KP6,
        .keypad7: .KEY_KP7,
        .keypad8: .KEY_KP8,
        .keypad9: .KEY_KP9,
        .keypad0: .KEY_KP0,
        .keypadPeriod: .KEY_KPDOT,
        .keypadEqualSign: .KEY_KPEQUAL,
        
        // MARK: - International / ISO
        .nonUSBackslash: .KEY_102ND,        // Key next to Left Shift on ISO
        // .nonUSPound: .KEY_UNKNOWN,       // Often maps to HASHTILDE (not in LinuxKeycode) or BACKSLASH alias
        
        // LANG Keys (Korean/Japanese specific)
        .LANG1: .KEY_HANGEUL,           // Korean Hangul / Japanese Kana
        .LANG2: .KEY_HANJA,             // Korean Hanja / Japanese Eisu
        .LANG3: .KEY_KATAKANA,
        .LANG4: .KEY_HIRAGANA,
        .LANG5: .KEY_ZENKAKUHANKAKU,
        
        // MARK: - Multimedia & Power
        .application: .KEY_MENU,        // Context Menu key
        .power: .KEY_POWER
    ]
    
    static func from(gameController keycode: GCKeyCode) -> LinuxKeycode {
        return gcToLinux[keycode] ?? .KEY_UNKNOWN
    }
}
