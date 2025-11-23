//
//  QUICServerIdentity.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Security

import CryptoKit

import SwiftASN1
import X509 // swift-certificates

enum QUICServerIdentitySanityCheckError: Error {
    case identityCastFailed
    case certificateCopyFailed(OSStatus)
    case privateKeyCopyFailed(OSStatus)
    case trustCreationFailed(OSStatus)
}

enum QUICServerIdentityCreationError: Error {
    case notImplemented
    
    case identityAlreadyExists
    case identityNotFound
    case keyGenerationFailed(OSStatus?)
    case publicKeyExportFailed
    case signatureFailed(OSStatus?)
    case certificateCreationFailed
    case identityCreationFailed
    case keychainWriteFailed(OSStatus)
    case keychainLookupFailed(OSStatus)
    case pkcs12ImportFailed(OSStatus)
    case pkcs12ExportFailed(OSStatus)
    case fileAlreadyExists
    case fileWriteFailed
}

public struct QUICServerIdentityCreationArgs {
    // Keychain의 경우 식별자 역할, P12 파일의 경우 파일 이름 역할을 합니다.
    public let identityLabel: String
    
    public let commonName: String
    public let organizationName: String
    public let organizationalUnitName: String
    public let countryName: String
    public let validityPeriodInDays: Int
    
    public init(identityLabel: String, commonName: String, organizationName: String, organizationalUnitName: String, countryName: String, validityPeriodInDays: Int) {
        self.identityLabel = identityLabel
        self.commonName = commonName
        self.organizationName = organizationName
        self.organizationalUnitName = organizationalUnitName
        self.countryName = countryName
        self.validityPeriodInDays = validityPeriodInDays
    }
}

public protocol QUICServerIdentity {
    static func createSelfSignedIdentity(args: QUICServerIdentityCreationArgs) throws -> Self
    
    func getServerIdentity() async throws -> sec_identity_t
}

// MARK: - Internal helpers

enum SelfSignedCertificateBuilder {
    static func createCertificateAndKey(args: QUICServerIdentityCreationArgs) throws -> (Certificate, P256.Signing.PrivateKey) {
        // 1. Key Pair 생성 (P256 권장, QUIC/TLS 1.3 친화적)
        // RSA를 꼭 써야 한다면 RSA 키 생성 로직을 유지하되, 여기서는 최신 트렌드인 P256을 예시로 듭니다.
        let key = P256.Signing.PrivateKey()
        
        // 2. 인증서 정보 구성
        let subjectName = try DistinguishedName {
            CommonName(args.commonName)
            OrganizationName(args.organizationName)
            OrganizationalUnitName(args.organizationalUnitName)
            CountryName(args.countryName)
        }
        
        let now = Date()
        let expiry = now.addingTimeInterval(TimeInterval(args.validityPeriodInDays * 24 * 60 * 60))
        
        // 3. 인증서 생성 및 서명 (Self-Signed)
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: Certificate.PublicKey(key.publicKey),
            notValidBefore: now,
            notValidAfter: expiry,
            issuer: subjectName,
            subject: subjectName,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: Certificate.Extensions {
                Critical(
                    BasicConstraints.isCertificateAuthority(maxPathLength: 0)
                )
                KeyUsage(digitalSignature: true, keyCertSign: true)
            },
            issuerPrivateKey: Certificate.PrivateKey(key)
        )
        
        return (certificate, key)
    }
   
}

public extension QUICServerIdentity {
    /// 서버 아이덴티티 (인증서)에 대한 Sanity Check를 실시합니다.
    /// - 인증서가 유효한지 확인합니다.
    ///
    /// - Parameters:
    ///   - strict: 엄격 모드 여부. 기본값은 `false` 입니다.
    ///             `true`로 설정하면 더 엄격한 검사를 수행합니다.
    ///
    func sanityCheck(strict: Bool = false) async throws -> Bool {
        let identityRef = try await getServerIdentity()
        let identityCF = identityRef as CFTypeRef
        guard CFGetTypeID(identityCF) == SecIdentityGetTypeID() else {
            throw QUICServerIdentitySanityCheckError.identityCastFailed
        }
        let identity = identityCF as! SecIdentity
        
        var certificate: SecCertificate?
        let certificateStatus = SecIdentityCopyCertificate(identity, &certificate)
        guard certificateStatus == errSecSuccess, let certificate else {
            throw QUICServerIdentitySanityCheckError.certificateCopyFailed(certificateStatus)
        }
        
        var privateKey: SecKey?
        let privateKeyStatus = SecIdentityCopyPrivateKey(identity, &privateKey)
        guard privateKeyStatus == errSecSuccess, privateKey != nil else {
            throw QUICServerIdentitySanityCheckError.privateKeyCopyFailed(privateKeyStatus)
        }
        
        let policy = SecPolicyCreateSSL(true, nil)
        
        var trust: SecTrust?
        let trustCreationStatus = SecTrustCreateWithCertificates(certificate, policy, &trust)
        guard trustCreationStatus == errSecSuccess, let trust else {
            throw QUICServerIdentitySanityCheckError.trustCreationFailed(trustCreationStatus)
        }
        
        if strict {
            // 시스템 트러스트 스토어를 기준으로 인증서를 검증합니다.
        } else {
            // self-signed 인증서도 허용하기 위해, 인증서를 Anchor로 추가합니다.
            SecTrustSetAnchorCertificates(trust, [certificate] as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, false)
        }
        
        if #available(macOS 10.15, *) {
            var error: CFError?
            let isTrusted = SecTrustEvaluateWithError(trust, &error)
            
            if let error {
                throw error
            }
            
            return isTrusted
        } else {
            var result = SecTrustResultType.invalid
            let status = SecTrustEvaluate(trust, &result)
            guard status == errSecSuccess else {
                return false
            }
            
            return result == .unspecified || result == .proceed
        }
    }
}

internal extension CFError {
    func asOSStatus() -> OSStatus {
        return OSStatus(CFErrorGetCode(self))
    }
}
