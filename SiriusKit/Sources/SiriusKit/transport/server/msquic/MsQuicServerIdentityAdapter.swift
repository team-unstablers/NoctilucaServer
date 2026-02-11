//
//  MsQuicServerIdentityAdapter.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 2/3/26.
//

import Foundation
import Security

import SwiftMsQuicHelper
import SiriusKitCore

import CryptoKit
internal import X509

private func generateAsciiPassword(count: Int) throws -> Data {
    let charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{}|;:,.<>?/"
    var password = try SRSecurity.shared.createSecureRandomBytes(count: 16)
    
    for i in 0..<count {
        let randomIndex = Int(password[i] % UInt8(charset.count))
        let char = charset[charset.index(charset.startIndex, offsetBy: randomIndex)]
        // swiftlint:disable:next force_unwrapping
        password[i] = char.asciiValue!
    }
    
    return consume password
}

/// SecIdentity를 MsQuic의 QuicCredentialConfig로 변환하는 어댑터
///
/// MsQuic은 PKCS#12 형식의 인증서를 요구하므로, SecIdentity를 PKCS#12로 export하여
/// 임시 파일로 저장한 뒤 MsQuic에 전달합니다.
/// 이 클래스가 deinit될 때 임시 파일이 자동으로 삭제됩니다.
final class MsQuicServerIdentityAdapter {
    enum AdapterError: Error {
        case pemExportFailed(OSStatus)
        case tempFileCreationFailed
        case identityNotAvailable
    }

    private let identity: any QUICServerIdentity

    /// QUICServerIdentity로부터 어댑터를 생성합니다.
    ///
    /// - Parameters:
    ///   - identity: QUICServerIdentity 프로토콜을 구현한 객체
    init(identity: any QUICServerIdentity) {
        self.identity = identity
    }

    /// MsQuic용 QuicCredentialConfig를 생성합니다.
    func createCredentialConfig() async throws -> QuicCredentialConfig {
        let secIdentity = try await identity.getServerIdentity()
        let intermediateChain = try await identity.getCertificateChain()
        let password = try generateAsciiPassword(count: 16)
        
        let pemCert = try Self.exportCertificates(identity: secIdentity, chain: intermediateChain)
        let privateKey = try secIdentity.extractPrivateKey()
        
        let keyAlgorithm = try privateKey.extractKeyAlgorithm()
        switch keyAlgorithm {
        case kSecAttrKeyTypeECSECPrimeRandom:
            let pemKey = try Self.exportPrivateKey(p256: privateKey)
            
            return QuicCredentialConfig(type: .certificatePem(
                key: consume pemKey,
                cert: consume pemCert,
                password: nil
            ))
            
        default:
            let pemKey = try Self.exportPrivateKey(privateKey, password: password)
            
            return QuicCredentialConfig(type: .certificatePem(
                key: consume pemKey,
                cert: consume pemCert,
                password: consume password
            ))
        }
    }
    
    /// exports certificate chain to PEM sequence format from SecIdentity
    private static func exportCertificates(identity: SecIdentity, chain: [SecCertificate]) throws -> Data {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)
        
        guard status == errSecSuccess, let leaf = certificate else {
            throw AdapterError.identityNotAvailable
        }

        let exportTarget = [leaf] + chain.filter { !$0.isSelfSignedCertificate() }
        var pemSequence = Data()

        for certificate in exportTarget {
            var pemData = try exportCertificateToPEM(certificate)
            if pemData.last != 0x0A {
                pemData.append(0x0A)
            }
            pemSequence.append(pemData)
        }

        return pemSequence
    }

    private static func exportCertificateToPEM(_ certificate: SecCertificate) throws -> Data {
        var certData: CFData?
        let exportStatus = SecItemExport(
            certificate,
            .formatPEMSequence,
            [],
            nil,
            &certData
        )

        guard exportStatus == errSecSuccess, let data = certData as Data? else {
            throw AdapterError.pemExportFailed(exportStatus)
        }

        return data
    }
    
    /// exports private key to PEM format from SecIdentity
    private static func exportPrivateKey(_ privateKey: SecKey, password: Data) throws -> Data {
        var keyParams = SecItemImportExportKeyParameters()
        keyParams.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
        let passphrase = password as CFData
        keyParams.passphrase = Unmanaged.passUnretained(passphrase)
        
        var keyData: CFData?
        let exportStatus = SecItemExport(
            privateKey,
            .formatWrappedPKCS8,
            [],
            &keyParams,
            &keyData
        )
        
        guard exportStatus == errSecSuccess, keyData != nil else {
            throw AdapterError.pemExportFailed(exportStatus)
        }
        
        let pemHeader = "-----BEGIN ENCRYPTED PRIVATE KEY-----\n"
        let pemFooter = "\n-----END ENCRYPTED PRIVATE KEY-----"
        let base64Body = (keyData as? Data)!.base64EncodedString(options: .lineLength64Characters)
        
        let pemString = pemHeader + base64Body + pemFooter
        
        guard let pemData = pemString.data(using: .utf8) else {
            throw AdapterError.pemExportFailed(-1)
        }
        
        return pemData
    }
    
    // FIXME: 지금의 내 기술력으론 PEM에 암호화를 걸 수가 없다.. ㅠ_ㅠ
    private static func exportPrivateKey(p256 privateKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(privateKey, &error) else {
            throw AdapterError.pemExportFailed(error?.takeUnretainedValue().asOSStatus() ?? -1)
        }
        
        let ckPrivateKey = try P256.Signing.PrivateKey(x963Representation: data as Data)
        return ckPrivateKey.pemRepresentation.data(using: .utf8)!
    }
}

fileprivate extension SecIdentity {
    func extractPrivateKey() throws -> SecKey {
        var privateKey: SecKey?
        let status = SecIdentityCopyPrivateKey(self, &privateKey)
        
        guard status == errSecSuccess, let key = privateKey else {
            throw MsQuicServerIdentityAdapter.AdapterError.identityNotAvailable
        }
        
        return key
    }
}

fileprivate extension SecKey {
    func extractKeyAlgorithm() throws -> CFString {
        let cfKeyAttributes = SecKeyCopyAttributes(self)
        
        guard let cfKeyAttributes,
              let keyAttributes = cfKeyAttributes as? [String: Any]
        else {
            throw MsQuicServerIdentityAdapter.AdapterError.identityNotAvailable
        }
        
        guard let keyType = keyAttributes[kSecAttrKeyType as String] as? String else {
            throw MsQuicServerIdentityAdapter.AdapterError.identityNotAvailable
        }
        
        return keyType as CFString
    }
}
