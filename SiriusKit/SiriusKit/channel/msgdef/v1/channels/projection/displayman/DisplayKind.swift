//
//  DisplayKind.swift
//  SiriusKit
//
//  Created by Codex on 1/10/26.
//

import Foundation

public struct DisplayKind: RawRepresentable, Hashable, Equatable {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    public static let unknown = Self(rawValue: 0)
    public static let `internal` = Self(rawValue: 1)
    public static let external = Self(rawValue: 2)
    public static let virtual = Self(rawValue: 3)
}
