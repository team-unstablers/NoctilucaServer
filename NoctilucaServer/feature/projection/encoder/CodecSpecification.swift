//
//  CodecDefinition.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation
import SiriusKit

enum CodecOptionsKey: String, Codable {
    /// 하드웨어 가속 사용 여부를 설정합니다. 항상 지켜지진 않습니다.
    /// @typedef { 'true' | 'forced' | 'false' }
    case hardwareAcceleration = "hardware-acceleration"
}

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
    }
    
    let fourCC: CodecFourCC
    
    var options: [CodecOptionsKey: String] = [:]
    var policy: CodecQualityPolicy = .respectClient
    
    init(fourCC: CodecFourCC) {
        self.fourCC = fourCC
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        fourCC = try container.decode(CodecFourCC.self, forKey: .fourCC)
        options = try container.decodeIfPresent([CodecOptionsKey: String].self, forKey: .options) ?? [:]
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(fourCC, forKey: .fourCC)
        try container.encode(options, forKey: .options)
    }
    
    private func mutatingOptions(_ key: CodecOptionsKey, value: String) -> Self {
        var spec = self
        
        spec.options[key] = value
        return spec
    }
    
    func hardwareAcceleration(forced: Bool = false) -> Self {
        return mutatingOptions(.hardwareAcceleration, value: forced ? "forced" : "true")
    }
}

extension CodecSpecification {
    /// Advanced Video Coding (H.264), MPEG-4 Part 10
    static let h264 = CodecSpecification(fourCC: .avc1)
    
    /// High Efficiency Video Coding (H.265), MPEG-H Part 2
    static let hevc = CodecSpecification(fourCC: .hvc1)
}
