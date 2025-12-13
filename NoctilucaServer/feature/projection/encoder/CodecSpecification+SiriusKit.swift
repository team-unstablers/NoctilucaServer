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
    /// 이.. 이딴식으로 이걸 구현해도 되는건가...
    fileprivate var pixelCount: Int {
        switch self {
        case .unlimited:
            // FIXME
            return 131072 * 131072
        case .sd480p:
            return 720 * 720
        case .hd720p:
            return 1280 * 1280
        case .hd1080p:
            return 1920 * 1920
        case .hd2k:
            return 2560 * 2560
        case .hd4k:
            return 3840 * 3840
        
        default:
            return 131072 * 131072
        }
    }
    
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
