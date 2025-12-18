//
//  CodecSpecification+SiriusKit.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation
import SiriusKit

extension CodecSpecification {
    init(siriusKit codec: SiriusKit.Codec) {
        self.fourCC = codec.fourCC
        if let cgSize = codec.size {
            self.maximumResolutionLevel = CodecResolutionLevel.fromCGSize(size: cgSize)
        } else {
            self.maximumResolutionLevel = .unlimited
        }
        self.options = CodecOptionsParser.parse(optionsString: codec.options)
        self.frameRate = Double(codec.frameRate ?? 0.0)
    }
    
    func toSiriusKitCodec() -> SiriusKit.Codec {
        var codec = SiriusKit.Codec(
            fourCC: self.fourCC,
            frameRate: Float(self.frameRate),
            size: CGSize(width: 0, height: 0),
            options: CodecOptionsParser.serialize(options: self.options),
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
