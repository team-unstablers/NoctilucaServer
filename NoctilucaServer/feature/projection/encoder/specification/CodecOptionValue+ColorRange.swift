//
//  CodecOptionValue+ColorDepth.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/20/25.
//

extension CodecOptionValue {
    /// Television-safe한 제한된 색상 범위를 사용합니다. (SDR: 16-235, HDR: 64-940)
    static let kColorRangeLimited = Self(rawValue: "limited")
    
    /// 전체 색상 범위를 사용합니다. (SDR: 0-255, HDR: 0-1023)
    static let kColorRangeFull = Self(rawValue: "full")
}
