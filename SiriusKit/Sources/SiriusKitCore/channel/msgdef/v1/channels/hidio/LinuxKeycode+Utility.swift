//
//  Keycode.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/18/25.
//

import Foundation

public extension LinuxKeycode {
    var isModifierKey: Bool {
        switch self {
        case .KEY_LEFTCTRL, .KEY_RIGHTCTRL,
             .KEY_LEFTSHIFT, .KEY_RIGHTSHIFT,
             .KEY_LEFTALT, .KEY_RIGHTALT,
             .KEY_LEFTMETA, .KEY_RIGHTMETA:
            return true
        default:
            return false
        }
    }
}
