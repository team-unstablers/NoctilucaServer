//
//  CodecParameterType.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/15/25.
//

import Foundation

public struct CodecParameterSetType: RawRepresentable, Hashable, Equatable, Sendable {
    public let rawValue: UInt64
    
    public init(rawValue: UInt64) {
        self.rawValue = rawValue
    }
    
    public init(fourCC: CodecFourCC, parameterSetType: UInt32) {
        self.rawValue = (UInt64(fourCC.rawValue) << 32) | UInt64(parameterSetType)
    }
    
    public init(fourCC: CodecFourCC, _ a: Character, _ b: Character, _ c: Character, _ d: Character) {
        let parameterSetType = ((UInt32(a.asciiValue!) << 24) | (UInt32(b.asciiValue!) << 16) | (UInt32(c.asciiValue!) << 8) | UInt32(d.asciiValue!))
        
        self.init(fourCC: fourCC, parameterSetType: parameterSetType)
    }
    
    public static let avc1SPS = CodecParameterSetType(fourCC: .avc1, "_", "S", "P", "S")
    public static let avc1PPS = CodecParameterSetType(fourCC: .avc1, "_", "P", "P", "S")
    
    public static let hvc1SPS = CodecParameterSetType(fourCC: .hvc1, "_", "S", "P", "S")
    public static let hvc1PPS = CodecParameterSetType(fourCC: .hvc1, "_", "P", "P", "S")
    public static let hvc1VPS = CodecParameterSetType(fourCC: .hvc1, "_", "V", "P", "S")
}
