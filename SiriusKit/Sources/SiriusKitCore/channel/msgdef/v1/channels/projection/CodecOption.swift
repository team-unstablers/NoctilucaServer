//
//  CodecOption.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation

public struct CodecOptionValue: RawRepresentable, Codable, Hashable, Equatable, Sendable {
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public struct CodecOptionKey: RawRepresentable, Codable, Hashable, Equatable, Sendable {
    public let rawValue: String
    
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
    ///
    /// Deprecated since Noctiluca 0.9.10 — ZRLE/MJPG/WebP 코덱이 제거되어 사용처가 없습니다.
    /// 향후 새 코덱이 동일 의미로 재사용할 수 있도록 키 정의는 유지합니다.
    public static let compressionLevel = Self(rawValue: "compression-level")

    /// 타일 사이즈를 설정합니다. (ZRLE / MJPG 전용)
    ///
    /// Deprecated since Noctiluca 0.9.10 — ZRLE/MJPG/WebP 코덱이 제거되어 사용처가 없습니다.
    /// 향후 새 코덱이 동일 의미로 재사용할 수 있도록 키 정의는 유지합니다.
    public static let tileSize = Self(rawValue: "tile-size")

    /// 양자화 레벨을 설정합니다. (ZRLE 전용, 그라데이션 압축률 향상용)
    /// @typedef { '0' | '1' | '2' | '3' }
    ///
    /// Deprecated since Noctiluca 0.9.10 — ZRLE 코덱이 제거되어 사용처가 없습니다.
    /// 향후 새 코덱이 동일 의미로 재사용할 수 있도록 키 정의는 유지합니다.
    public static let quantizeLevel = Self(rawValue: "quantize-level")
}

public struct CodecOptions: Codable, Equatable, Hashable, Sendable {
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

    enum CodingKeys: String, CodingKey {
        case mandatory
        case `optional`
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mandatoryRaw = (try? container.decode([String: String].self, forKey: .mandatory)) ?? [:]
        let optionalRaw = (try? container.decode([String: String].self, forKey: .optional)) ?? [:]
        self.mandatory = Dictionary(uniqueKeysWithValues: mandatoryRaw.map {
            (CodecOptionKey(rawValue: $0.key), CodecOptionValue(rawValue: $0.value))
        })
        self.optional = Dictionary(uniqueKeysWithValues: optionalRaw.map {
            (CodecOptionKey(rawValue: $0.key), CodecOptionValue(rawValue: $0.value))
        })
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        let mandatoryRaw = Dictionary(uniqueKeysWithValues: mandatory.map { ($0.key.rawValue, $0.value.rawValue) })
        let optionalRaw = Dictionary(uniqueKeysWithValues: self.optional.map { ($0.key.rawValue, $0.value.rawValue) })
        try container.encode(mandatoryRaw, forKey: .mandatory)
        try container.encode(optionalRaw, forKey: .optional)
    }
}

