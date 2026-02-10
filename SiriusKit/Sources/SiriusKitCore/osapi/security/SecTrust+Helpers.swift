//
//  SecTrust+Helpers.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 2/11/26.
//

import Foundation
import Security

public extension SecTrust {
    /// 이 인증서로 트러스트 객체를 만듭니다.
    /// Parameters:
    /// - isServer: SSL 서버용 트러스트 객체를 만들지 여부입니다. 기본값은 `true`입니다.
    /// - allowSelfSigned: 자가 서명된 인증서를 허용할지 여부입니다. 기본값은 `false`입니다.
    ///                    true로 설정하면, 인증서 자기 자신을 trust의 anchor로써 설정합니다.
    ///                    이렇게 함으로써 자가 서명은 허용하면서 인증서의 유효 기간 등은 여전히 검증할 수 있습니다.
    static func create(leaf: SecCertificate, chain: [SecCertificate] = [], isServer: Bool = true, allowSelfSigned: Bool = false) throws -> SecTrust {
        var trust: SecTrust?
        let sslPolicy = SecPolicyCreateSSL(isServer, nil)
        
        let certificates = ([leaf] + chain) as CFArray
        let status = SecTrustCreateWithCertificates(certificates, sslPolicy, &trust)
        
        guard status == errSecSuccess, let trust else {
            // FIXME: OSStatus 좀 이쁘게 넘기는 법 없냐고 ㅠ
            throw SRSecurityError.operationFailed(error: nil)
        }
        
        if allowSelfSigned {
            // 자가 서명된 인증서인 경우, 인증서 자체를 anchor로 설정하여 유효 기간 등은 검증하면서도 신뢰할 수 있도록 합니다.
            SecTrustSetAnchorCertificates(trust, certificates)
            SecTrustSetAnchorCertificatesOnly(trust, false)
        }
        
        return trust
    }

    
    /// 이 트러스트 객체를 평가합니다.
    @available(macOS 10.15, *)
    func evaluate() throws -> Bool {
        var error: CFError?
        
        let isTrusted = SecTrustEvaluateWithError(self, &error)
        
        if let error {
            throw error
        }
        
        return isTrusted
    }
}
