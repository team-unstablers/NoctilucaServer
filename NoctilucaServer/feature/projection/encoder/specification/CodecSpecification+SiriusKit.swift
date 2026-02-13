//
//  CodecSpecification+SiriusKit.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation
import SiriusKit

extension CodecSpecification {
    /*
    init(siriusKit codec: SiriusKit.Codec) {
        self.fourCC = codec.fourCC
        if let cgSize = codec.size {
            self.maximumResolutionLevel = CodecResolutionLevel.fromCGSize(size: cgSize)
        } else {
            self.maximumResolutionLevel = .unlimited
        }
        self.options = codec.options
        self.frameRate = Double(codec.frameRate ?? 0.0)
    }
     */
    
    fileprivate static let optionalCodecOptionPairs: [(CodecOptionKey, CodecOptionValue)] = [
        (.colorFormat, .kColorFormatAuto),
        (.hardwareAcceleration, .kHardwareAccelerationAuto),
        (.profile, .kProfileAuto),
        (.displayDensity, .kDisplayDensityAuto)
    ]
    
    var siriusKitCodecOptions: CodecOptions {
        var options = CodecOptions()
        
        for (key, value) in self.options {
            if CodecSpecification.optionalCodecOptionPairs.contains(where: { $0.0 == key && $0.1 == value }) {
                options.optional[key] = value
            } else {
                options.mandatory[key] = value
            }
        }
        
        return consume options
    }
    
    func toSiriusKitCodec() -> SiriusKit.Codec {
        let siriusQuality: SiriusKit.Codec.Quality
        switch self.quality {
        case .auto(let mode):
            siriusQuality = .auto(mode: AutoQualityMode(rawValue: mode))
        case .constantBitrate(let bitrateKbps):
            siriusQuality = .constantBitrate(bitrateKbps: bitrateKbps)
        case .variableBitrate(let targetBitrateKbps, let maxBitrateKbps):
            siriusQuality = .variableBitrate(targetBitrateKbps: targetBitrateKbps, maxBitrateKbps: maxBitrateKbps)
        case .fixedQuality(let factor):
            siriusQuality = .fixedQuality(factor: factor)
        case .lossless(let mode):
            siriusQuality = .lossless(mode: LosslessQualityMode(rawValue: mode))
        }

        let codec = SiriusKit.Codec(
            fourCC: self.fourCC,
            frameRate: Float(self.frameRate),
            size: SRSize(width: 0, height: 0),
            options: self.siriusKitCodecOptions,
            quality: siriusQuality
        )

        return codec
    }
}

extension CodecResolutionLevel {

    
    /// CodecResolutionLevel을 만듭니다. (다만 Requirement 관점으로)
    static func fromCGSize(size: CGSize) -> CodecResolutionLevel {
        let pixels = Int(size.width * size.height)
        
        if pixels <= CodecResolutionLevel.sd480p.pixelCount {
            return .sd480p
        } else if pixels <= CodecResolutionLevel.hd720p.pixelCount {
            return .hd720p
        } else if pixels <= CodecResolutionLevel.hd1080p.pixelCount {
            return .hd1080p
        } else if pixels <= CodecResolutionLevel.hd2k.pixelCount {
            return .hd2k
        } else if pixels <= CodecResolutionLevel.hd4k.pixelCount {
            return .hd4k
        } else {
            return .hd4k
        }
    }
}
