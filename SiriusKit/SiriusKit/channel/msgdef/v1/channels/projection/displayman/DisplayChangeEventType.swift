//
//  DisplayChangeEventType.swift
//  SiriusKit
//
//  Created by Codex on 1/10/26.
//

import Foundation

public struct DisplayChangeEventType: OptionSet, Hashable, Equatable {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    public static let none = Self([])
    public static let connected = Self(rawValue: 1 << 0)
    public static let disconnected = Self(rawValue: 1 << 1)
    public static let modified = Self(rawValue: 1 << 2)
    public static let becamePrimary = Self(rawValue: 1 << 3)
}
