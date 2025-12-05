//
//  SecuritySettings.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation
import SiriusKit

extension AppSettings {
    struct Security: Category {
        var authMethods: [AllowedAuthMethod] = []
    }
    
    /// 트랜스포트 레이어
    struct Transport: Category {
        /// 서버 버전을 알리지 않기
        /// - 서버 버전을 클라이언트에게 알리지 않는다.
        /// - 보안성이 강화될 수 있을지도 모르지만.. 호환성이 떨어질 수 있다.
        var disableServerVersionAnnouncement: Bool = false
        
        /// 지원하는 기능 목록을 알리지 않기
        /// - 서버가 지원하는 기능 목록을 클라이언트에게 알리지 않는다.
        /// - 보안성이 강화될 수 있을지도 모르지만.. 호환성이 떨어질 수 있다.
        var disableSupportedFeaturesAnnouncement: Bool = false
        
        var motd: String = ""
        var authChallengeMessage: String = ""
    }
    
    struct QUICTransport: Category {
        enum TLSIdentity: Codable {
            case keychain(identifier: String)
            case pemFile(certFilePath: String, keyFilePath: String)
        }
        
        var listenPort: UInt16 = SiriusQUICDefaultPort
        
        /// 자동 구성된 TLS 설정 사용하기
        /// - true 설정 시 자가 서명 인증서를 자동으로 발급하여 사용한다
        /// - 인증서 만료 시 갱신, 분실 시 재발급 등을 자동으로 처리한다
        var tlsUseAutoconf: Bool = true
        
        /// 엄격한 유효성 검사 사용하기
        /// - 시스템의 트러스트 스토어를 기준으로 인증서가 신뢰 가능한지 엄격하게 검사한다
        ///   (= self-signed 인증서나 신뢰할 수 없는 CA에서 발급한 인증서를 사용하여 서버 가동 시도 시 실패하도록 한다)
        var tlsStrictValidation: Bool = false
        
        /// 서버 TLS 인증서 및 개인 키 설정
        /// - TODO: assert(tlsUseAutoconf && identity.type != .pemFile)
        var identity: TLSIdentity? = nil
    }
}
