//
//  CodecFourCC+Audio.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 1/28/26.
//

import Foundation

public extension CodecFourCC {
    /// Opus Audio Codec
    static let opus = CodecFourCC("O", "P", "U", "S")

    /// G.711 mu-law (PCMU)
    static let pcmu = CodecFourCC("P", "C", "M", "U")

    /// G.711 A-law (PCMA)
    static let pcma = CodecFourCC("P", "C", "M", "A")
}
