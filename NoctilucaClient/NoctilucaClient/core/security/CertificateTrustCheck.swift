//
//  CertificateTrustCheck.swift
//  NoctilucaClient
//

import Foundation
import Security

/// 인증서 체인에 시스템 트러스트 스토어에서 명시적으로 거부된 인증서가 포함되어 있는지 검사합니다.
///
/// `.user` 및 `.admin` 도메인의 `SecTrustSettings`를 확인하며,
/// 하나라도 `SecTrustSettingsResult.deny`로 설정된 인증서가 있으면 `true`를 반환합니다.
///
/// - Note: macOS 전용입니다. iOS에서는 항상 `false`를 반환합니다.
func containsDeniedCertificate(in certificates: [SecCertificate]) -> Bool {
    #if os(macOS)
    let domains: [SecTrustSettingsDomain] = [.user, .admin]
    return certificates.contains { cert in
        domains.contains { domain in
            var trustSettings: CFArray?
            guard SecTrustSettingsCopyTrustSettings(cert, domain, &trustSettings) == errSecSuccess else {
                return false
            }
            return (trustSettings as? [CFDictionary] ?? [])
                .contains { setting in
                    if let setting = setting as? [String: Any],
                       let result = setting[kSecTrustSettingsResult as String] as? Int,
                       result == SecTrustSettingsResult.deny.rawValue {
                        return true
                    }
                    return false
                }
        }
    }
    #else
    return false
    #endif
}
