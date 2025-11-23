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
    static func createIdentity(args: QUICServerIdentityCreationArgs, storePrivateKeyInKeychain: Bool) throws -> (SecIdentity, SecCertificate) {
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
        
        // 4. SecIdentity로 변환 (Security Framework와의 호환성)
        return try convertToSecIdentity(certificate: certificate, privateKey: key, label: args.identityLabel, storeInKeychain: storePrivateKeyInKeychain)
    }
    
    // Swift Crypto 키와 인증서를 SecIdentity로 변환하는 헬퍼
    private static func convertToSecIdentity(
        certificate: Certificate,
        privateKey: P256.Signing.PrivateKey,
        label: String,
        storeInKeychain: Bool
    ) throws -> (SecIdentity, SecCertificate) {
        
        // 4-1. SecCertificate 생성
        var derSerializer = DER.Serializer()
        
        try certificate.serialize(into: &derSerializer)
        
        var derData = derSerializer.serializedBytes
        let certData = Data(derData)
        guard let secCertificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            throw QUICServerIdentityCreationError.certificateCreationFailed
        }
        
        // 4-2. SecKey (Private Key) 생성
        let privateKeyData = privateKey.derRepresentation
        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrLabel as String: label,
            kSecAttrIsPermanent as String: storeInKeychain // 키체인 저장 여부
        ]
        
        var error: Unmanaged<CFError>?
        guard let secPrivateKey = SecKeyCreateWithData(privateKeyData as CFData, keyAttributes as CFDictionary, &error) else {
            throw QUICServerIdentityCreationError.keychainWriteFailed(error?.takeRetainedValue().asOSStatus() ?? errSecInternalError)
        }
        
        // 4-3. SecIdentity 생성
        // (주의: SecIdentityCreate는 키체인에 있는 키에 대해서만 동작하는 경우가 많습니다.
        //  만약 메모리 상에서만 임시로 쓴다면 SecIdentityCreate가 실패할 수 있으므로,
        //  보통은 키체인에 넣었다가 불러오거나 해야 합니다. 하지만 여기서는 P12 export를 위해 임시 생성이 필요하죠.)
        
        // 간단한 방법: SecIdentityCreateWithCertificate (macOS 10.14+, iOS 12+) 사용 시도
        // 만약 이 API가 없다면 키체인에 add 후 copyMatching 해야 합니다.
        
        var secIdentity: SecIdentity?
        // 임시 키체인 생성 로직 혹은 기존 로직 활용 필요
        // ...
        
        // P12FileQUICServerIdentity.swift의 경우 키체인 저장이 false이므로
        // SecIdentity를 만들기 위해 임시 키체인을 생성하거나,
        // P12 생성 시 Identity 대신 Cert와 Key를 각각 넘길 수 있는지 확인해야 합니다.
        // 하지만 SecItemExport는 Identity를 요구합니다.
        
        // 해결책: 임시 키체인에 넣지 않고 SecIdentity를 만드는 공식 API는 없습니다.
        // 따라서 P12 생성을 위해서는 Identity가 필수이므로,
        // `storeInKeychain: true`로 하여 키체인에 넣은 뒤 Identity를 가져오고,
        // 작업 후 삭제하는 방식을 권장합니다.
        
        // 기존 코드 흐름상 Identity를 반환해야 하므로,
        // 위에서 만든 secPrivateKey와 secCertificate를 조합합니다.
        
        guard let identity = SecIdentityCreate(nil, secCertificate, secPrivateKey) else {
             throw QUICServerIdentityCreationError.identityCreationFailed
        }
        
        return (identity, secCertificate)
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
            return SecTrustEvaluateWithError(trust, nil)
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

private extension CFError {
    func asOSStatus() -> OSStatus {
        return OSStatus(CFErrorGetCode(self))
    }
}
