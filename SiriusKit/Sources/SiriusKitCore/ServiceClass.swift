//
//  ServiceClass.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 2/10/26.
//

import Foundation

/// 서비스에서 전송될 컨텐츠의 유형 / 우선순위
public enum ServiceClass {
    ///  사용자 입력 (가장 높음)
    case userInput
    
    /// 실시간 비디오 스트림
    case realtimeVideo
    /// 실시간 오디오 스트림
    case realtimeAudio
    
    /// 시그널링
    case signaling
    
    /// 백그라운드 태스크 (파일 전송 등...) (가장 낮음)
    case background
}

public extension ServiceClass {
    static let `default`: Self = .signaling
}

package extension ServiceClass {
    var asMsQuicPriority: UInt16 {
        switch self {
        case .userInput:
            return 0xBEEF // 장난 치지 마세요! 💢
            
        case .realtimeVideo:
            return 0x87FF
            
        case .realtimeAudio:
            return 0x8000
            
        case .signaling:
            return 0x7FFF
            
        case .background:
            return 0x3000
        }
    }
    
}
