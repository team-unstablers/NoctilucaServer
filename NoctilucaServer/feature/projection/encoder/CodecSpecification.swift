//
//  CodecDefinition.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation
import SiriusKit


enum CodecQualityPolicy: String, Hashable, Equatable, Codable {
    /// 클라이언트의 품질 요청을 최대한 존중합니다.
    case respectClient = "respect-client"
    
    /// 최대한 균형 있게 결정합니다.
    case balanced = "balanced"
    
    /// 서버의 품질 설정을 우선시합니다. 클라이언트의 요청은 무시됩니다.
    case overrideFromServer = "override-from-server"
}

struct CodecSpecification: Codable {
    enum CodingKeys: String, CodingKey {
        case fourCC = "fourcc"
        case options = "options"
        case extras = "extras"
    }
    
    let fourCC: CodecFourCC
    var options: [CodecOptionKey: CodecOptionValue] = [:]
    var extras: String = ""
    
    
    // 초당 프레임 수. 0.0인 경우 자동 설정됨을 의미합니다.
    var frameRate: Double = 0.0
    
    // XXX: 간단 설정을 위한 속성 - 최대 해상도 레벨
    var maximumResolutionLevel: CodecResolutionLevel = .unlimited

    init(fourCC: CodecFourCC) {
        self.fourCC = fourCC
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        fourCC = try container.decode(CodecFourCC.self, forKey: .fourCC)
        options = try container.decode([CodecOptionKey: CodecOptionValue].self, forKey: .options)
        extras = try container.decodeIfPresent(String.self, forKey: .extras) ?? ""
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(fourCC, forKey: .fourCC)
        try container.encode(options, forKey: .options)
        try container.encode(extras, forKey: .extras)
    }
    
    func option(_ key: CodecOptionKey) -> CodecOptionValue? {
        return options[key]
    }
    
    func option(_ key: CodecOptionKey, _ value: CodecOptionValue) -> Self {
        var spec = self
        
        spec.options[key] = value
        return spec
    }
}

extension CodecSpecification: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(fourCC.rawValue)
        hasher.combine(options)
    }
}

extension CodecSpecification {
    /// Advanced Video Coding (H.264), MPEG-4 Part 10
    static let h264 = CodecSpecification(fourCC: .avc1)
        .option(.hardwareAcceleration, .kHardwareAccelerationTrue)
        .option(.profile, .kProfileAuto)
        .option(.colorFormat, .kColorFormatAuto)
    
    /// High Efficiency Video Coding (H.265), MPEG-H Part 2
    static let hevc = CodecSpecification(fourCC: .hvc1)
        .option(.hardwareAcceleration, .kHardwareAccelerationTrue)
        .option(.profile, .kProfileAuto)
        .option(.colorFormat, .kColorFormatAuto)
}

extension CodecSpecification {
    var displayTitle: String {
        switch fourCC {
        case .avc1:
            return "Advanced Video Coding (H.264)"
        case .hvc1:
            return "High Efficiency Video Coding (H.265)"
        default:
            return "Unknown Codec (\(fourCC.stringRepresentation))"
        }
    }
    
    var description: String {
        var entries: [String] = []
        
        let profile = options[.profile] ?? .kProfileAuto
        
        switch profile {
        case .kProfileHigh:
            entries.append("High 프로파일")
        case .kProfileMain:
            entries.append("Main 프로파일")
        case .kProfileBaseline:
            entries.append("Baseline 프로파일")
        default:
            entries.append("자동 프로파일")
        }
        
        let colorFormat = options[.colorFormat] ?? .kColorFormatAuto
        
        switch colorFormat {
        case .kColorFormatAuto:
            entries.append("자동 색상 포맷")
        case .kColorFormatYUV420:
            entries.append("YUV 4:2:0")
        case .kColorFormatYUV444:
            entries.append("YUV 4:4:4")
        default:
            entries.append("알 수 없는 색상 포맷")
        }
        
        let hardwareAcceleration = options[.hardwareAcceleration] ?? .kHardwareAccelerationFalse
        
        switch hardwareAcceleration {
        case .kHardwareAccelerationTrue:
            entries.append("가능한 경우 하드웨어 가속 사용")
        case .kHardwareAccelerationForced:
            entries.append("하드웨어 가속 강제 사용")
        default:
            entries.append("하드웨어 가속 사용 안 함")
        }
        
        return entries.joined(separator: ", ")
    }
}
