//
//  CodecOptionValue+ColorDepth.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/20/25.
//

extension CodecOptionValue {
    /// Standard Dynamic Range
    static let kDynamicRangeSDR = Self(rawValue: "sdr")
    
    /// High Dynamic Range
    static let kDynamicRangeHDR = Self(rawValue: "hdr")
}
