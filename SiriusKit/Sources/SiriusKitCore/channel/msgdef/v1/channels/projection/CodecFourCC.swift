//
//  CodecFourCC.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation

public struct CodecFourCC: RawRepresentable, Codable, Equatable, Sendable {
    public var rawValue: UInt32
    
    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }
    
    public init(_ a: Character, _ b: Character, _ c: Character, _ d: Character) {
        self.rawValue = ((UInt32(a.asciiValue!) << 24) | (UInt32(b.asciiValue!) << 16) | (UInt32(c.asciiValue!) << 8) | UInt32(d.asciiValue!))
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let stringValue = try container.decode(String.self)
        
        guard stringValue.count == 4 else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "FourCC string must be exactly 4 characters.")
        }
        
        let characters = Array(stringValue)
        self.init(characters[0], characters[1], characters[2], characters[3])
    }
    
    public var stringRepresentation: String {
        let a = Character(UnicodeScalar((rawValue >> 24) & 0xFF)!)
        let b = Character(UnicodeScalar((rawValue >> 16) & 0xFF)!)
        let c = Character(UnicodeScalar((rawValue >> 8) & 0xFF)!)
        let d = Character(UnicodeScalar(rawValue & 0xFF)!)
        
        return String([a, b, c, d])
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(self.stringRepresentation)
    }
    
}

extension CodecFourCC: CustomDebugStringConvertible {
    public var debugDescription: String {
        let hexString = String(format: "0x%08X", self.rawValue)
        
        // "FourCC (AVC1, 0x....)"
        return "FourCC (\(self.stringRepresentation), \(hexString))"
    }
}

public extension CodecFourCC {
    /// Advanced Video Coding (H.264), MPEG-4 Part 10
    static let avc1 = CodecFourCC("A", "V", "C", "1")
    
    /// High Efficiency Video Coding (H.265), MPEG-H Part 2
    static let hvc1 = CodecFourCC("H", "V", "C", "1")
    
    /// Google VP8
    static let vp80 = CodecFourCC("V", "P", "8", "0")

    /// ZRLE (Zlib Run-Length Encoding), RLE + Zstd
    static let zrle = CodecFourCC("Z", "R", "L", "E")

    /// Motion JPEG
    static let mjpg = CodecFourCC("M", "J", "P", "G")
    
    /// WebP
    static let webp = CodecFourCC("W", "E", "B", "P")
}
