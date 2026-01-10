//
//  DisplayColorDepth.swift
//  SiriusKit
//
//  Created by Codex on 1/10/26.
//

import Foundation

public struct DisplayColorDepth: RawRepresentable, Hashable, Equatable {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    public static let unknown = Self(rawValue: 0)
    public static let grayscale = Self(rawValue: 1)
    public static let indexed16Color = Self(rawValue: 2)
    public static let indexed256Color = Self(rawValue: 3)
    public static let color8Bit = Self(rawValue: 4)
    public static let color10Bit = Self(rawValue: 5)
}
