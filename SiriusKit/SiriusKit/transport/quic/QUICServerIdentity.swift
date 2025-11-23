//
//  QUICServerIdentity.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Security

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

/*
enum SelfSignedCertificateBuilder {
    static func createIdentity(args: QUICServerIdentityCreationArgs, storePrivateKeyInKeychain: Bool) throws -> (SecIdentity, SecCertificate) {
        // Generate key pair
        let keyLabelData = args.identityLabel.data(using: .utf8) ?? Data()
        let privateKeyAttrs: [String: Any] = [
            kSecAttrIsPermanent as String: storePrivateKeyInKeychain,
            kSecAttrApplicationTag as String: keyLabelData,
            kSecAttrLabel as String: args.identityLabel
        ]
        
        let keygenAttrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
            kSecPrivateKeyAttrs as String: privateKeyAttrs
        ]
        
        var keyError: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(keygenAttrs as CFDictionary, &keyError) else {
            throw QUICServerIdentityCreationError.keyGenerationFailed(keyError?.takeRetainedValue().asOSStatus())
        }
        
        guard let publicKey = SecKeyCopyPublicKey(privateKey),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data?
        else {
            throw QUICServerIdentityCreationError.publicKeyExportFailed
        }
        
        // Build certificate
        let certificateData = try buildCertificateData(args: args, publicKeyData: publicKeyData, signingKey: privateKey)
        guard let certificate = SecCertificateCreateWithData(nil, certificateData as CFData) else {
            throw QUICServerIdentityCreationError.certificateCreationFailed
        }
        
        guard let identity = SecIdentityCreate(nil, certificate, privateKey) else {
            throw QUICServerIdentityCreationError.identityCreationFailed
        }
        
        return (identity, certificate)
    }
    
    private static func buildCertificateData(
        args: QUICServerIdentityCreationArgs,
        publicKeyData: Data,
        signingKey: SecKey
    ) throws -> Data {
        // Version [0] EXPLICIT v3
        let version = ASN1.contextSpecific(tag: 0, constructed: true, ASN1.integer(from: 2))
        
        let serialNumber = ASN1.serialNumber()
        let signatureAlgorithm = ASN1.algorithmIdentifier(oid: ASN1.OID.sha256WithRSAEncryption)
        let name = ASN1.distinguishedName(
            commonName: args.commonName,
            organization: args.organizationName,
            organizationalUnit: args.organizationalUnitName,
            country: args.countryName
        )
        let validity = ASN1.validity(notBefore: Date().addingTimeInterval(-300), days: args.validityPeriodInDays)
        let subjectPublicKeyInfo = ASN1.subjectPublicKeyInfo(publicKeyData: publicKeyData)
        
        let tbsCertificate = ASN1.sequence([
            version,
            ASN1.integer(from: serialNumber),
            signatureAlgorithm,
            name,
            validity,
            name,
            subjectPublicKeyInfo
        ])
        
        var signError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            signingKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            tbsCertificate as CFData,
            &signError
        ) as Data? else {
            throw QUICServerIdentityCreationError.signatureFailed(signError?.takeRetainedValue().asOSStatus())
        }
        
        let certificate = ASN1.sequence([
            tbsCertificate,
            signatureAlgorithm,
            ASN1.bitString(signature)
        ])
        
        return certificate
    }
}

enum ASN1 {
    enum OID {
        static let rsaEncryption: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
        static let sha256WithRSAEncryption: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x0B]
        static let countryName: [UInt8] = [0x55, 0x04, 0x06]
        static let organizationName: [UInt8] = [0x55, 0x04, 0x0A]
        static let organizationalUnitName: [UInt8] = [0x55, 0x04, 0x0B]
        static let commonName: [UInt8] = [0x55, 0x04, 0x03]
    }
    
    static func length(_ length: Int) -> Data {
        if length < 128 {
            return Data([UInt8(length)])
        }
        
        var value = length
        var bytes: [UInt8] = []
        while value > 0 {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        }
        
        return Data([0x80 | UInt8(bytes.count)]) + Data(bytes)
    }
    
    static func tlv(tag: UInt8, _ content: Data) -> Data {
        var data = Data([tag])
        data.append(length(content.count))
        data.append(content)
        return data
    }
    
    static func sequence(_ elements: [Data]) -> Data {
        return tlv(0x30, elements.reduce(Data(), +))
    }
    
    static func set(_ elements: [Data]) -> Data {
        return tlv(0x31, elements.reduce(Data(), +))
    }
    
    static func integer(from int: Int) -> Data {
        var value = int
        var bytes: [UInt8] = []
        repeat {
            bytes.insert(UInt8(value & 0xFF), at: 0)
            value >>= 8
        } while value > 0
        
        return integer(from: Data(bytes))
    }
    
    static func integer(from data: Data) -> Data {
        var content = data
        if let first = content.first, first & 0x80 != 0 {
            content.insert(0x00, at: 0)
        }
        return tlv(0x02, content)
    }
    
    static func oid(_ bytes: [UInt8]) -> Data {
        return tlv(0x06, Data(bytes))
    }
    
    static func printableString(_ string: String) -> Data {
        return tlv(0x13, Data(string.utf8))
    }
    
    static func utf8String(_ string: String) -> Data {
        return tlv(0x0C, Data(string.utf8))
    }
    
    static func utcTime(_ date: Date) -> Data {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        let string = formatter.string(from: date)
        return tlv(0x17, Data(string.utf8))
    }
    
    static func bitString(_ data: Data, unusedBits: UInt8 = 0) -> Data {
        return tlv(0x03, Data([unusedBits]) + data)
    }
    
    static func contextSpecific(tag: UInt8, constructed: Bool = true, _ content: Data) -> Data {
        let base: UInt8 = constructed ? 0xA0 : 0x80
        return tlv(base | tag, content)
    }
    
    // MARK: Certificate helpers
    
    static func serialNumber() -> Data {
        var bytes = Data(count: 16)
        _ = bytes.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, ptr.count, ptr.baseAddress!)
        }
        if let first = bytes.first, first & 0x80 != 0 {
            bytes.insert(0x00, at: 0)
        }
        return bytes
    }
    
    static func algorithmIdentifier(oid: [UInt8]) -> Data {
        let null = tlv(0x05, Data())
        return sequence([self.oid(oid), null])
    }
    
    static func distinguishedName(
        commonName: String,
        organization: String,
        organizationalUnit: String,
        country: String
    ) -> Data {
        var rdns: [Data] = []
        
        rdns.append(set([sequence([oid(OID.countryName), printableString(country)])]))
        rdns.append(set([sequence([oid(OID.organizationName), utf8String(organization)])]))
        rdns.append(set([sequence([oid(OID.organizationalUnitName), utf8String(organizationalUnit)])]))
        rdns.append(set([sequence([oid(OID.commonName), utf8String(commonName)])]))
        
        return sequence(rdns)
    }
    
    static func validity(notBefore: Date, days: Int) -> Data {
        let notAfter = Calendar.current.date(byAdding: .day, value: days, to: notBefore) ?? notBefore
        return sequence([
            utcTime(notBefore),
            utcTime(notAfter)
        ])
    }
    
    static func subjectPublicKeyInfo(publicKeyData: Data) -> Data {
        let algId = algorithmIdentifier(oid: OID.rsaEncryption)
        return sequence([
            algId,
            bitString(publicKeyData)
        ])
    }
}
 */

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
