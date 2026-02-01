//
//  AudioCodecSpecification.swift
//  NoctilucaClient
//
//  Created by Codex on 1/30/26.
//

import Foundation
import SiriusKitClient

struct AudioCodecSpecification: Codable, Sendable {
    enum CodingKeys: String, CodingKey {
        case fourCC = "fourcc"
        case options = "options"
        case extras = "extras"
    }

    let fourCC: CodecFourCC
    var options: [CodecOptionKey: CodecOptionValue]
    var extras: String = ""

    init(fourCC: CodecFourCC) {
        self.fourCC = fourCC
        self.options = [:]
    }

    init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            fourCC = .opus
            options = [:]
            extras = ""
            return
        }

        if let decodedFourCC = try? container.decode(CodecFourCC.self, forKey: .fourCC) {
            fourCC = decodedFourCC
        } else if let rawValue = try? container.decode(UInt32.self, forKey: .fourCC) {
            fourCC = CodecFourCC(rawValue: rawValue)
        } else {
            fourCC = .opus
        }

        if let decodedOptions = try? container.decode([CodecOptionKey: CodecOptionValue].self, forKey: .options) {
            options = decodedOptions
        } else if let decodedOptions = try? container.decode(CodecOptions.self, forKey: .options) {
            options = decodedOptions.optional.merging(decodedOptions.mandatory) { _, newValue in newValue }
        } else {
            options = [:]
        }

        extras = (try? container.decodeIfPresent(String.self, forKey: .extras)) ?? ""
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
    
    func also(_ transformFn: (inout AudioCodecSpecification) -> Void) -> Self {
        var spec = self
        
        transformFn(&spec)
        
        return spec
    }
}

extension AudioCodecSpecification: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(fourCC.rawValue)
        hasher.combine(options)
        hasher.combine(extras)
    }
}

extension AudioCodecSpecification {
    static let opus = AudioCodecSpecification(fourCC: .opus)
    static let pcmu = AudioCodecSpecification(fourCC: .pcmu)
    static let pcma = AudioCodecSpecification(fourCC: .pcma)
}

extension AudioCodecSpecification {
    var displayTitle: String {
        switch fourCC {
        case .opus:
            return "Opus"
        case .pcmu:
            return "G.711 u-law"
        case .pcma:
            return "G.711 a-law"
        default:
            return "Unknown Codec (\(fourCC.stringRepresentation))"
        }
    }

    var description: String {
        return self.displayTitle
    }
}
