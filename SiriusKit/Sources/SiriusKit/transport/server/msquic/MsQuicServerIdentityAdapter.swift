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

private func generateAsciiPassword(count: Int) throws -> Data {
    let charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()-_=+[]{}|;:,.<>?/"
    var password = try SRSecurity.shared.createSecureRandomBytes(count: 16)
    
    for i in 0..<count {
        let randomIndex = Int(password[i] % UInt8(charset.count))
        let char = charset[charset.index(charset.startIndex, offsetBy: randomIndex)]
        // swiftlint:disable:next force_cast
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
        var password = try generateAsciiPassword(count: 16)
        
        let pemCert = try Self.exportCertificate(identity: secIdentity)
        let pemKey = try Self.exportPrivateKey(identity: secIdentity, password: password)
        
        return QuicCredentialConfig(type: .certificatePem(
            key: consume pemKey,
            cert: consume pemCert,
            password: consume password
        ))
    }
    
    // TODO: support certificate chain
    /// exports certificate to PEM format from SecIdentity
    private static func exportCertificate(identity: SecIdentity) throws -> Data {
        var certificate: SecCertificate?
        let status = SecIdentityCopyCertificate(identity, &certificate)
        
        guard status == errSecSuccess, let cert = certificate else {
            throw AdapterError.identityNotAvailable
        }
        
        var certData: CFData?
        let exportStatus = SecItemExport(
            cert,
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
    private static func exportPrivateKey(identity: SecIdentity, password: Data) throws -> Data {
        var privateKey: SecKey?
        let status = SecIdentityCopyPrivateKey(identity, &privateKey)
        
        guard status == errSecSuccess, let key = privateKey else {
            throw AdapterError.identityNotAvailable
        }
        
        var keyParams = SecItemImportExportKeyParameters()
        keyParams.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
        let passphrase = password as CFData
        keyParams.passphrase = Unmanaged.passUnretained(passphrase)
        
        var keyData: CFData?
        let exportStatus = SecItemExport(
            key,
            .formatWrappedPKCS8,
            [],
            &keyParams,
            &keyData
        )
        
        guard exportStatus == errSecSuccess, let data = keyData as Data? else {
            throw AdapterError.pemExportFailed(exportStatus)
        }
        
        let pemHeader = "-----BEGIN ENCRYPTED PRIVATE KEY-----\n"
        let pemFooter = "\n-----END ENCRYPTED PRIVATE KEY-----"
        let base64Body = data.base64EncodedString(options: .lineLength64Characters)
        
        let pemString = pemHeader + base64Body + pemFooter
        
        guard let pemData = pemString.data(using: .utf8) else {
            throw AdapterError.pemExportFailed(-1)
        }
        
        return pemData
    }
}