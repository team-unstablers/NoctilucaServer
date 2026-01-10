//
//  DisplayDynamicRange.swift
//  SiriusKit
//
//  Created by Codex on 1/10/26.
//

import Foundation

public struct DisplayDynamicRange: RawRepresentable, Hashable, Equatable {
    public let rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    public static let sdr = Self(rawValue: 0)
    public static let hdr = Self(rawValue: 1)
}
