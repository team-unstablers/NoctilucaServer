//
//  CodecOption.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation

public struct CodecOptionValue: RawRepresentable, Codable, Hashable, Equatable {
    public var rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct CodecOptionKey: RawRepresentable, Codable, Hashable, Equatable {
    public var rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    /// 색상 포맷을 설정합니다.
    public static let colorFormat = Self(rawValue: "color-format")

    /// 하드웨어 가속 사용 여부를 설정합니다. 항상 지켜지진 않습니다.
    /// @typedef { 'true' | 'forced' | 'false' }
    public static let hardwareAcceleration = Self(rawValue: "hardware-acceleration")
    
    /// 코덱의 프로파일을 설정합니다.
    public static let profile = Self(rawValue: "profile")
    
    /// 코덱 레벨을 설정합니다.
    public static let level = Self(rawValue: "level")
    
    /// 색상 깊이를 설정합니다.
    /// TODO: 삭제해야됨 (profile이 이를 대체함)
    public static let colorDepth = Self(rawValue: "color-depth")
    
    /// 다이내믹 레인지를 설정합니다.
    public static let dynamicRange = Self(rawValue: "dynamic-range")
    
    /// 색상 레인지를 설정합니다.
    public static let colorRange = Self(rawValue: "color-range")
    
    /// 디스플레이 밀도를 설정합니다.
    public static let displayDensity = Self(rawValue: "display-density")
    
    /// 압축 레벨을 설정합니다. (ZRLE / MJPG 전용)
    public static let compressionLevel = Self(rawValue: "compression-level")
}

public struct CodecOptions: Codable, Equatable, Hashable {
    /// '필수' 옵션들 - 해당 옵션들이 서로 지원되지 않으면 호환되지 않는다고 판정됩니다
    public var mandatory: [CodecOptionKey: CodecOptionValue]
    /// '선택' 옵션들 - 희망 사항으로써 둡니다. 해당 옵션들이 서로 지원되지 않아도 호환된다고 판정됩니다
    public var `optional`: [CodecOptionKey: CodecOptionValue]
    
    public init() {
        self.mandatory = [:]
        self.optional = [:]
    }
    
    public init(mandatory: [CodecOptionKey: CodecOptionValue], optional: [CodecOptionKey: CodecOptionValue]) {
        self.mandatory = mandatory
        self.optional = optional
    }
}

