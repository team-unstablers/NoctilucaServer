//
//  CodecOption.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation

struct CodecOptions: Codable, Equatable {
    var mandatory: [CodecOptionKey: CodecOptionValue] = [:]
    var `optional`: [CodecOptionKey: CodecOptionValue] = [:]
}

struct CodecOptionValue: RawRepresentable, Codable, Hashable, Equatable {
    var rawValue: String
    
    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

struct CodecOptionKey: RawRepresentable, Codable, Hashable, Equatable {
    var rawValue: String
    
    init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    /// 색상 포맷을 설정합니다.
    static let colorFormat = Self(rawValue: "color-format")

    /// 하드웨어 가속 사용 여부를 설정합니다. 항상 지켜지진 않습니다.
    /// @typedef { 'true' | 'forced' | 'false' }
    static let hardwareAcceleration = Self(rawValue: "hardware-acceleration")
    
    /// 코덱의 프로파일을 설정합니다.
    static let profile = Self(rawValue: "profile")
    
    /// 코덱 레벨을 설정합니다.
    static let level = Self(rawValue: "level")
    
    /// 색상 깊이를 설정합니다.
    static let colorDepth = Self(rawValue: "color-depth")
    
    /// 다이내믹 레인지를 설정합니다.
    static let dynamicRange = Self(rawValue: "dynamic-range")
    
    /// 색상 레인지를 설정합니다.
    static let colorRange = Self(rawValue: "color-range")
    
    /// 디스플레이 밀도를 설정합니다.
    static let displayDensity = Self(rawValue: "display-density")
}
