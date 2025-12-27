//
//  KeySequence.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/27/25.
//

import Foundation
import SiriusKitClient

struct KeySequence: Hashable, Equatable, Codable {
    let modifier: Set<LinuxKeycode>
    let key: LinuxKeycode
    
    init(modifier: Set<LinuxKeycode>, key: LinuxKeycode) {
        self.modifier = modifier
        self.key = key
    }
    
    func addModifier(_ modifier: LinuxKeycode) -> Self {
        return KeySequence(modifier: self.modifier.union([modifier]), key: self.key)
    }
    
    func setKey(_ key: LinuxKeycode) -> Self {
        return KeySequence(modifier: self.modifier, key: key)
    }
}

extension KeySequence {
    static let empty = KeySequence(modifier: [], key: .KEY_UNKNOWN)
}

extension KeySequence: CustomStringConvertible {
    fileprivate var modifierDescription: String {
        // 정렬 순서: Control, Option, Shift, Command
        
        guard !modifier.isEmpty else {
            return ""
        }
        
        var description: String = ""
        
        if modifier.contains(.KEY_LEFTCTRL) {
            description.append(LinuxKeycode.KEY_LEFTCTRL.appleSymbol!)
        }
        
        if modifier.contains(.KEY_LEFTALT) {
            description.append(LinuxKeycode.KEY_LEFTALT.appleSymbol!)
        }
        
        if modifier.contains(.KEY_LEFTSHIFT) {
            description.append(LinuxKeycode.KEY_LEFTSHIFT.appleSymbol!)
        }
        
        if modifier.contains(.KEY_LEFTMETA) {
            description.append(LinuxKeycode.KEY_LEFTMETA.appleSymbol!)
        }
        
        return description
    }
    
    var description: String {
        guard self != .empty else {
            return "(없음)"
        }
        
        if key == .KEY_UNKNOWN {
            return modifierDescription
        }
        
        return (modifierDescription + (key.appleSymbol ?? key.appleDescription ?? key.description))
    }
}
