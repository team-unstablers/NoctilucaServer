//
//  CodecDefinition.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation
import SiriusKit

extension CodecSpecification {
    /// 호스트에서 주어진 스펙대로의 인코더를 실현할 수 있는지 여부를 반환합니다.
    func isRealizable() -> Bool {
        switch self.fourCC {
        case .avc1, .hvc1:
            return VTVideoEncoder.isSupported(codec: self)
            
        case .mjpg, .zrle, .webp:
            // 소프트웨어 인코더 지원
            return true
            
        default:
            return false
        }
    }
}


extension SiriusKit.Codec {
    /// 호스트에서 주어진 스펙대로의 인코더를 실현할 수 있는지 여부를 반환합니다.
    func isRealizable() -> Bool {
        switch self.fourCC {
        case .avc1, .hvc1:
            return true
        case .mjpg, .zrle, .webp:
            return true
        default:
            return false
        }
    }
}
