//
//  QUICServerIdentity.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Security

import CryptoKit
import _CryptoExtras

internal import SwiftASN1
internal import X509 // swift-certificates
import SiriusKitCore

public enum QUICServerIdentityLoadError: Error {
    /// 지정된 아이덴티티가 존재하지 않습니다.
    case identityNotFound
    
    /// 아이덴티티가 중복으로 존재합니다. (Keychain에서 동일한 라벨로 여러 아이덴티티가 존재하는 경우)
    case conflictingIdentitiesFound
}

// TODO: LLM이 생성한 사용하지 않는 케이스 제거 검토
public enum QUICServerIdentitySanityCheckError: Error {
    case identityCastFailed
    case certificateCopyFailed(OSStatus)
    case privateKeyCopyFailed(OSStatus)
    case trustCreationFailed(OSStatus)
}

// TODO: LLM이 생성한 사용하지 않는 케이스 제거 검토
public enum QUICServerIdentityCreationError: Error {
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

public enum IdentityKeyType {
    case p256
    case rsa2048
    case rsa4096

    var secKeyType: CFString {
        switch self {
        case .p256:
            return kSecAttrKeyTypeECSECPrimeRandom
        case .rsa2048, .rsa4096:
            return kSecAttrKeyTypeRSA
        }
    }

    var keySizeInBits: Int {
        switch self {
        case .p256:
            return 256
        case .rsa2048:
            return 2048
        case .rsa4096:
            return 4096
        }
    }
}

enum IdentityPrivateKey {
    case p256(P256.Signing.PrivateKey)
    case rsa(_RSA.Signing.PrivateKey)

    var derRepresentation: Data {
        switch self {
        case .p256(let key):
            return key.derRepresentation
        case .rsa(let key):
            return key.pkcs8DERRepresentation
        }
    }

    var certificatePrivateKey: Certificate.PrivateKey {
        switch self {
        case .p256(let key):
            return Certificate.PrivateKey(key)
        case .rsa(let key):
            return Certificate.PrivateKey(key)
        }
    }

    var certificatePublicKey: Certificate.PublicKey {
        switch self {
        case .p256(let key):
            return Certificate.PublicKey(key.publicKey)
        case .rsa(let key):
            return Certificate.PublicKey(key.publicKey)
        }
    }

    static func generate(keyType: IdentityKeyType) throws -> IdentityPrivateKey {
        switch keyType {
        case .p256:
            return .p256(P256.Signing.PrivateKey())
        case .rsa2048:
            return .rsa(try _RSA.Signing.PrivateKey(keySize: .bits2048))
        case .rsa4096:
            return .rsa(try _RSA.Signing.PrivateKey(keySize: .bits4096))
        }
    }
}

public struct QUICServerIdentityInfo {
    public let commonName: String
    public let fingerprint: Data
    public let notBefore: Date
    public let notAfter: Date
}

public struct QUICServerIdentityCreationArgs {
    // Keychain의 경우 식별자 역할, P12 파일의 경우 파일 이름 역할을 합니다.
    public let identityLabel: String
    public let keyType: IdentityKeyType

    public let commonName: String
    public let organizationName: String
    public let organizationalUnitName: String
    public let countryName: String
    public let validityPeriodInDays: Int

    public init(identityLabel: String, keyType: IdentityKeyType = .p256, commonName: String, organizationName: String, organizationalUnitName: String, countryName: String, validityPeriodInDays: Int) {
        self.identityLabel = identityLabel
        self.keyType = keyType
        self.commonName = commonName
        self.organizationName = organizationName
        self.organizationalUnitName = organizationalUnitName
        self.countryName = countryName
        self.validityPeriodInDays = validityPeriodInDays
    }
}

public protocol QUICServerIdentity: Sendable {
    static func createSelfSignedIdentity(args: QUICServerIdentityCreationArgs) throws -> Self

    func getServerIdentity() async throws -> SecIdentity
    func getCertificateChain() async throws -> [SecCertificate]
}

// MARK: - Internal helpers

enum SelfSignedCertificateBuilder {
    static func createCertificateAndKey(args: QUICServerIdentityCreationArgs) throws -> (Certificate, IdentityPrivateKey) {
        // 1. Key Pair 생성 (P256 권장, QUIC/TLS 1.3 친화적)
        // RSA를 꼭 써야 한다면 RSA 키 생성 로직을 유지하되, 여기서는 최신 트렌드인 P256을 예시로 듭니다.
        let key = try IdentityPrivateKey.generate(keyType: args.keyType)

        let signatureAlgorithm: Certificate.SignatureAlgorithm
        switch key {
        case .p256:
            signatureAlgorithm = .ecdsaWithSHA256
        case .rsa:
            signatureAlgorithm = .sha256WithRSAEncryption
        }

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
            publicKey: key.certificatePublicKey,
            notValidBefore: now,
            notValidAfter: expiry,
            issuer: subjectName,
            subject: subjectName,
            signatureAlgorithm: signatureAlgorithm,
            extensions: Certificate.Extensions {
                Critical(BasicConstraints.notCertificateAuthority)
                KeyUsage(digitalSignature: true, keyEncipherment: true, keyAgreement: true)
                try ExtendedKeyUsage([.serverAuth])
            },
            issuerPrivateKey: key.certificatePrivateKey
        )

        return (certificate, key)
    }

}

public extension QUICServerIdentity {
    func getCertificateChain() async throws -> [SecCertificate] {
        return []
    }

    func secCertificate() async throws -> SecCertificate {
        let identityRef = try await getServerIdentity()

        let identityCF = identityRef as CFTypeRef
        guard CFGetTypeID(identityCF) == SecIdentityGetTypeID() else {
            throw QUICServerIdentitySanityCheckError.identityCastFailed
        }

        // swiftlint:disable:next force_cast
        let identity = identityCF as! SecIdentity

        var certificate: SecCertificate?
        let certificateStatus = SecIdentityCopyCertificate(identity, &certificate)
        guard certificateStatus == errSecSuccess, let certificate else {
            throw QUICServerIdentitySanityCheckError.certificateCopyFailed(certificateStatus)
        }

        return certificate
    }

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

        // swiftlint:disable:next force_cast
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
        
        let trust = try SecTrust.create(leaf: certificate, allowSelfSigned: !strict)
        return try trust.evaluate()
    }

    func identityInfo() async throws -> QUICServerIdentityInfo {
        let identityRef = try await getServerIdentity()

        let identityCF = identityRef as CFTypeRef
        guard CFGetTypeID(identityCF) == SecIdentityGetTypeID() else {
            throw QUICServerIdentitySanityCheckError.identityCastFailed
        }

        // swiftlint:disable:next force_cast
        let identity = identityCF as! SecIdentity

        var certificate: SecCertificate?
        let certificateStatus = SecIdentityCopyCertificate(identity, &certificate)
        guard certificateStatus == errSecSuccess, let certificate else {
            throw QUICServerIdentitySanityCheckError.certificateCopyFailed(certificateStatus)
        }

        guard let commonName = certificate.extractCommonName(),
              let fingerprint = certificate.extractFingerprint(),
              let notBefore = certificate.extractNotBefore(),
              let notAfter = certificate.extractNotAfter()
        else {
            throw QUICServerIdentitySanityCheckError.certificateCopyFailed(-1)
        }

        return QUICServerIdentityInfo(
            commonName: commonName,
            fingerprint: fingerprint,
            notBefore: notBefore,
            notAfter: notAfter
        )
    }
}

internal extension CFError {
    func asOSStatus() -> OSStatus {
        return OSStatus(CFErrorGetCode(self))
    }
}
