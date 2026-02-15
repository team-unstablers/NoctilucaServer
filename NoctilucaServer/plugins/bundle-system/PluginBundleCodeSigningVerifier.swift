//
//  PluginBundleCodeSigningVerifier.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/12/26.
//

import Foundation
import Security

import SiriusKit

/// 코드 서명 검증 결과
enum CodeSigningVerificationResult {
    /// Apple Developer 서명이 유효하며, Team ID가 확인됨
    case validSignature(teamID: String, identity: String?, certificates: [SecCertificate])

    /// Ad-hoc 서명 (Team ID 없음)
    case adHocSignature

    /// 서명 없음
    case unsigned

    /// 검증 실패 (서명 손상 등)
    case invalid(error: OSStatus)
}

/// Security.framework를 이용한 코드 서명 검증 유틸리티
struct PluginBundleCodeSigningVerifier {
    static let teamUnstablersTeamID = "XHA76UVA95"

    /// 번들의 코드 서명을 검증한다.
    static func verify(bundleURL: URL) -> CodeSigningVerificationResult {
        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(bundleURL as CFURL, [], &staticCode)

        guard createStatus == errSecSuccess, let code = staticCode else {
            return .invalid(error: createStatus)
        }

        // 서명 유효성 검사
        let validityStatus = SecStaticCodeCheckValidity(
            code,
            SecCSFlags(rawValue: kSecCSCheckAllArchitectures),
            nil
        )

        switch validityStatus {
        case errSecSuccess:
            break
        case errSecCSUnsigned:
            return .unsigned
        default:
            return .invalid(error: validityStatus)
        }

        // 서명 정보 추출
        var signingInfo: CFDictionary?
        let infoStatus = SecCodeCopySigningInformation(
            code,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInfo
        )

        guard infoStatus == errSecSuccess, let info = signingInfo as? [String: Any] else {
            return .invalid(error: infoStatus)
        }

        // 인증서 체인 추출
        let certificates = (info[kSecCodeInfoCertificates as String] as? [SecCertificate]) ?? []
        let identity = certificates.first?.extractCommonName()

        // Team ID 추출
        if let teamID = info[kSecCodeInfoTeamIdentifier as String] as? String {
            return .validSignature(teamID: teamID, identity: identity, certificates: certificates)
        }

        return .adHocSignature
    }

    /// 검증 결과와 보안 정책을 비교하여 허용 여부를 판단한다.
    static func shouldAllow(
        result: CodeSigningVerificationResult,
        policy: PluginBundleSecurityPolicy
    ) -> Result<Void, PluginBundleRegistryError> {
        switch policy {
        case .disallowAll:
            return .failure(.securityPolicyViolation(
                currentPolicy: policy,
                requiredPolicy: .allowTeamUnstablers
            ))

        case .allowTeamUnstablers:
            guard case .validSignature(let teamID, _, _) = result,
                  teamID == teamUnstablersTeamID
            else {
                return .failure(.securityPolicyViolation(
                    currentPolicy: policy,
                    requiredPolicy: .allowSigned
                ))
            }
            return .success(())

        case .allowSigned:
            guard case .validSignature = result else {
                return .failure(.securityPolicyViolation(
                    currentPolicy: policy,
                    requiredPolicy: .allowAll
                ))
            }
            return .success(())

        case .allowAll:
            return .success(())
        }
    }
}
