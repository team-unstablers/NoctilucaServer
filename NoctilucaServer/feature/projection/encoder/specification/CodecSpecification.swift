//
//  CodecDefinition.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation
import SiriusKit


enum CodecNegotiationPolicy: String, Hashable, Equatable, Codable {
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
        case frameRate = "frame_rate"
        case maximumResolutionLevel = "maximum_resolution_level"
    }
    
    let fourCC: CodecFourCC
    var options: [CodecOptionKey: CodecOptionValue]
    var extras: String = ""
    
    
    // 초당 프레임 수. 0.0인 경우 자동 설정됨을 의미합니다.
    var frameRate: Double = 0.0
    
    // XXX: 간단 설정을 위한 속성 - 최대 해상도 레벨
    var maximumResolutionLevel: CodecResolutionLevel = .unlimited
    
    init(fourCC: CodecFourCC) {
        self.fourCC = fourCC
        self.options = [:]
    }
    
    init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            fourCC = .avc1
            options = [:]
            extras = ""
            frameRate = 0.0
            maximumResolutionLevel = .unlimited
            return
        }

        if let decodedFourCC = try? container.decode(CodecFourCC.self, forKey: .fourCC) {
            fourCC = decodedFourCC
        } else if let rawValue = try? container.decode(UInt32.self, forKey: .fourCC) {
            fourCC = CodecFourCC(rawValue: rawValue)
        } else {
            fourCC = .avc1
        }

        if let decodedOptions = try? container.decode([CodecOptionKey: CodecOptionValue].self, forKey: .options) {
            options = decodedOptions
        } else if let decodedOptions = try? container.decode(CodecOptions.self, forKey: .options) {
            options = decodedOptions.optional.merging(decodedOptions.mandatory) { _, newValue in newValue }
        } else {
            options = [:]
        }

        extras = (try? container.decodeIfPresent(String.self, forKey: .extras)) ?? ""
        frameRate = (try? container.decodeIfPresent(Double.self, forKey: .frameRate)) ?? 0.0
        maximumResolutionLevel = (try? container.decodeIfPresent(CodecResolutionLevel.self, forKey: .maximumResolutionLevel)) ?? .unlimited
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(fourCC, forKey: .fourCC)
        try container.encode(options, forKey: .options)
        try container.encode(extras, forKey: .extras)
        try container.encode(frameRate, forKey: .frameRate)
        try container.encode(maximumResolutionLevel, forKey: .maximumResolutionLevel)
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
        .option(.hardwareAcceleration, .kHardwareAccelerationAuto)
        .option(.profile, .kProfileAuto)
        .option(.colorFormat, .kColorFormatAuto)
        .option(.dynamicRange, .kDynamicRangeSDR)
        .option(.colorRange, .kColorRangeLimited)
        .option(.displayDensity, .kDisplayDensityAuto)
    
    /// High Efficiency Video Coding (H.265), MPEG-H Part 2
    static let hevc = CodecSpecification(fourCC: .hvc1)
        .option(.hardwareAcceleration, .kHardwareAccelerationAuto)
        .option(.profile, .kProfileAuto)
        .option(.colorFormat, .kColorFormatAuto)
        .option(.dynamicRange, .kDynamicRangeSDR)
        .option(.colorRange, .kColorRangeLimited)
        .option(.displayDensity, .kDisplayDensityAuto)
    
    static let zrle = CodecSpecification(fourCC: .zrle)
        .option(.colorFormat, .kColorFormatRGB565)
        .option(.compressionLevel, .init(rawValue: "3"))
        .option(.tileSize, .kTileSize128x128)
        .option(.quantizeLevel, .kQuantizeLevel2)
        .option(.maxFrameRate, .init(rawValue: "15"))
    
    static let mjpg = CodecSpecification(fourCC: .mjpg)
        .option(.colorFormat, .kColorFormatAuto)
        .option(.tileSize, .kTileSize256x256)
        .option(.compressionLevel, .init(rawValue: "28"))
}

extension CodecSpecification {
    var displayTitle: String {
        switch fourCC {
        case .avc1:
            return "Advanced Video Coding (H.264)"
        case .hvc1:
            return "High Efficiency Video Coding (H.265)"
        case .zrle:
            return "Run-Length Encoding (RLE) + Zstd"
        case .mjpg:
            return "Motion JPEG"
            
        default:
            return "Unknown Codec (\(fourCC.stringRepresentation))"
        }
    }
    
    fileprivate var commonDescription: String {
        var entries: [String] = []
        
        let profile = self.option(.profile) ?? .kProfileAuto
        
        switch profile {
        case .kProfileH264High:
            entries.append("High 프로파일")
        case .kProfileH264Main:
            entries.append("Main 프로파일")
        case .kProfileH264Baseline:
            entries.append("Baseline 프로파일")
            
        case .kProfileHEVCMain:
            entries.append("Main 프로파일")
            
        case .kProfileHEVCMain10:
            entries.append("Main10 프로파일")
            
        default:
            entries.append("자동 프로파일")
        }
        
        let colorFormat = self.option(.colorFormat) ?? .kColorFormatAuto
        
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
        
        let hardwareAcceleration = self.option(.hardwareAcceleration) ?? .kHardwareAccelerationFalse
        
        switch hardwareAcceleration {
        case .kHardwareAccelerationAuto:
            entries.append("가능한 경우 하드웨어 가속 사용")
        case .kHardwareAccelerationFalse:
            entries.append("하드웨어 가속 사용 안 함")
        default:
            entries.append("가능한 경우 하드웨어 가속 사용")
        }
        
        let dynamicRange = self.option(.dynamicRange) ?? .kDynamicRangeSDR
        
        if dynamicRange == .kDynamicRangeHDR {
            entries.append("HDR 지원 활성화됨")
        }
        
        return entries.joined(separator: ", ")
    }
    
    var description: String {
        switch self.fourCC {
        case .zrle, .mjpg:
            return "압축 레벨 \(self.option(.compressionLevel)?.rawValue ?? "1")"
        default:
            return commonDescription
        }
    }
}

/*
extension CodecSpecification {
    /// HACK: YUV420에 대한 sanity check를 실시한다: 가로/세로가 8의 배수여야 함
    func __sanityCheck() -> Bool {
        guard self.options[.colorFormat] != .kColorFormatYUV444,
              let size = self.size
        else {
            return true
        }
        
        // YUV420 포맷은 가로/세로가 8의 배수여야 함
        return size.width.truncatingRemainder(dividingBy: 8) == 0 &&
        size.height.truncatingRemainder(dividingBy: 8) == 0
    }
}
*/
