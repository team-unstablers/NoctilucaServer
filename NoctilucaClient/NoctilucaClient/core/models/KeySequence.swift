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

struct KeySequenceMatcher {
    private var sequence: KeySequence = .empty
    private var requiredKeys: Set<LinuxKeycode> = []
    private var isLatched: Bool = false

    mutating func update(sequence: KeySequence) {
        guard self.sequence != sequence else {
            return
        }

        self.sequence = sequence
        self.requiredKeys = sequence.modifier.union([sequence.key])
        self.isLatched = false
    }

    mutating func handleKeyDown(keyCode: LinuxKeycode,
                                pressedKeys: Set<LinuxKeycode>,
                                isActive: Bool) -> Bool {
        guard isActive else {
            return false
        }

        guard !isLatched else {
            return false
        }

        guard keyCode == sequence.key else {
            return false
        }

        guard pressedKeys == requiredKeys else {
            return false
        }

        isLatched = true
        return true
    }

    mutating func handleKeyUp(pressedKeys: Set<LinuxKeycode>) {
        guard isLatched else {
            return
        }

        if !requiredKeys.isSubset(of: pressedKeys) {
            isLatched = false
        }
    }
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
