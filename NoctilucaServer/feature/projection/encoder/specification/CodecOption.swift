//
//  CodecOption.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation

struct CodecOptionValue: RawRepresentable, Codable, Hashable, Equatable {
    var rawValue: String
    
    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

enum CodecOptionKey: String, Codable, Hashable, Equatable {
    /// 색상 포맷을 설정합니다.
    case colorFormat = "color-format"

    /// 하드웨어 가속 사용 여부를 설정합니다. 항상 지켜지진 않습니다.
    /// @typedef { 'true' | 'forced' | 'false' }
    case hardwareAcceleration = "hardware-acceleration"
    
    /// 코덱의 프로파일을 설정합니다.
    case profile = "profile"
    
    /// 코덱 레벨을 설정합니다.
    case level = "level"
    
    /// 색상 깊이를 설정합니다.
    case colorDepth = "color-depth"
    
    /// 다이내믹 레인지를 설정합니다.
    case dynamicRange = "dynamic-range"
    
    /// 색상 레인지를 설정합니다.
    case colorRange = "color-range"
    
    /// 디스플레이 밀도를 설정합니다.
    case displayDensity = "display-density"
}
