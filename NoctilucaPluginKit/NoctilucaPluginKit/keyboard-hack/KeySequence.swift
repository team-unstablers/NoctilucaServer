//
//  KeySequence.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 2/14/26.
//

public struct KeySequence: Hashable, Equatable, Codable, Sendable {
    public let modifier: Set<LinuxKeycode>
    public let key: LinuxKeycode
    
    public init(modifier: Set<LinuxKeycode>, key: LinuxKeycode) {
        self.modifier = modifier
        self.key = key
    }
    
    public func addModifier(_ modifier: LinuxKeycode) -> Self {
        return KeySequence(modifier: self.modifier.union([modifier]), key: self.key)
    }
    
    public func setKey(_ key: LinuxKeycode) -> Self {
        return KeySequence(modifier: self.modifier, key: key)
    }
}

extension KeySequence {
    public static let empty = KeySequence(modifier: [], key: .KEY_UNKNOWN)
}
