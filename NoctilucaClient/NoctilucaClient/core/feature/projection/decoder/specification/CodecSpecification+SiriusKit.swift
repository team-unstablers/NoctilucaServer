//
//  CodecSpecification+SiriusKit.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation
import SiriusKitClient

extension CodecSpecification {
    fileprivate static let optionalCodecOptionPairs: [(CodecOptionKey, CodecOptionValue)] = [
        (.colorFormat, .kColorFormatAuto),
        (.hardwareAcceleration, .kHardwareAccelerationAuto),
        (.profile, .kProfileAuto),
        (.displayDensity, .kDisplayDensityAuto),
        (.dynamicRange, .kDynamicRangeSDR),
        (.dynamicRange, .kDynamicRangeHDR),
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
    
    func toSiriusKitCodec() -> SiriusKitClient.Codec {
        var codec = SiriusKitClient.Codec(
            fourCC: self.fourCC,
            frameRate: Float(self.frameRate),
            
            // FIXME
            size: nil,
            options: self.siriusKitCodecOptions,
            
            // FIXME - CodecSpecification에 품질 정책 없음!!
            quality: .auto(mode: .balancedPriority)
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
