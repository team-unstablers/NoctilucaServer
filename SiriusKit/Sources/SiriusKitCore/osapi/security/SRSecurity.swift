//
//  SRSecurity.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Security

import CryptoKit
import _CryptoExtras

internal import SwiftASN1
package import X509

package typealias SRSwiftX509Certificate = Certificate
package typealias SRCryptoKitP256PrivateKey = P256.Signing.PrivateKey

package enum SRSecurityError: Error {
    case createItemFailed(error: (any Error)?)
    case operationFailed(error: (any Error)?)
}

#if os(macOS)
package enum SRCertificateTrustScope {
    case user
    case admin

    package var asSecTrustSettingsDomain: SecTrustSettingsDomain {
        switch self {
        case .user:
            return .user
        case .admin:
            return .admin
        }
    }
}
#endif

/// 'S'i'R'ius Keychain - macOS Security.framework 의 Security 관련 기능을 wrap합니다.
public class SRSecurity {
    public static let shared = SRSecurity()
    
    public func createSecureRandomBytes(count: Int) throws -> Data {
        var buffer = Data(count: count)
        
        let status = buffer.withUnsafeMutableBytes { ptr in
            SecRandomCopyBytes(kSecRandomDefault, count, ptr.baseAddress!)
        }
        
        guard status == errSecSuccess else {
            // TODO: OSStatus를 따로 넘기거나 하는게 좋을 것 같은데
            throw SRSecurityError.operationFailed(error: nil)
        }
        
        return consume buffer
    }

    package func createCertificate(using certificate: SRSwiftX509Certificate) -> Result<SecCertificate, SRSecurityError> {
        var derSerializer = DER.Serializer()

        do {
            try certificate.serialize(into: &derSerializer)

            let derData = derSerializer.serializedBytes
            let certData = Data(derData)

            guard let secCertificate = SecCertificateCreateWithData(nil, certData as CFData) else {
                return .failure(.createItemFailed(error: nil))
            }

            return .success(secCertificate)
        } catch {
            return .failure(.createItemFailed(error: error))
        }
    }

    package func createTrust(from certificate: SecCertificate) -> Result<SecTrust, SRSecurityError> {
        var trust: SecTrust?

        let status = SecTrustCreateWithCertificates(certificate, SecPolicyCreateBasicX509(), &trust)

        guard status == errSecSuccess, let trustedTrust = trust else {
            return .failure(.createItemFailed(error: nil))
        }

        return .success(trustedTrust)
    }

    package func createPrivateKey(from privateKey: SRCryptoKitP256PrivateKey, with applicationLabel: Data) -> Result<SecKey, SRSecurityError> {
        let x963KeyData = privateKey.x963Representation

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256,
            // kSecAttrApplicationLabel as String: applicationLabel, // <--- 여기가 핵심 연결 고리!
            kSecAttrIsExtractable as String: true
        ]

        var error: Unmanaged<CFError>?

        guard let secKey = SecKeyCreateWithData(x963KeyData as CFData, attributes as CFDictionary, &error) else {
            return .failure(.createItemFailed(error: error?.takeRetainedValue()))
        }

        return .success(secKey)
    }

    package func createRSAPrivateKey(from privateKey: _RSA.Signing.PrivateKey, with applicationLabel: Data) -> Result<SecKey, SRSecurityError> {
        let keyData = privateKey.derRepresentation

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: privateKey.keySizeInBits,
            // kSecAttrApplicationLabel as String: applicationLabel,
            kSecAttrIsExtractable as String: true
        ]

        var error: Unmanaged<CFError>?

        guard let secKey = SecKeyCreateWithData(keyData as CFData, attributes as CFDictionary, &error) else {
            return .failure(.createItemFailed(error: error?.takeRetainedValue()))
        }

        return .success(secKey)
    }

    package func createIdentity(certificate: SecCertificate, privateKey: SecKey) -> Result<SecIdentity, SRSecurityError> {
        guard let identity = SecIdentityCreate(nil, certificate, privateKey) else {
            return .failure(.createItemFailed(error: nil))
        }

        return .success(identity)
    }

#if os(macOS)
    package func trustCertificate(_ certificate: SecCertificate, scope: SRCertificateTrustScope) -> Result<Void, SRSecurityError> {
        let trustSettings: [String: Any] = [
            kSecTrustSettingsResult as String: SecTrustSettingsResult.trustRoot.rawValue
        ]

        let status = SecTrustSettingsSetTrustSettings(
            certificate,
            scope.asSecTrustSettingsDomain,
            trustSettings as CFTypeRef
        )

        guard status == errSecSuccess else {
            return .failure(.operationFailed(error: nil))
        }

        return .success(())
    }
#endif
}
