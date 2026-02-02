//
//  PEMFileQUICServerIdentity.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Security
import CryptoKit

internal import SwiftASN1
internal import X509

public class PEMFileQUICServerIdentity: QUICServerIdentity {
    private let certPath: String
    private let keyPath: String

    // Set this to protect the private key; currently only unencrypted PEM is emitted.
    // private static let keyPassphrase: String? = "changeit"
    private static let keyPassphrase: String? = nil

    public required init(using certPath: String, key keyPath: String) {
        self.certPath = certPath
        self.keyPath = keyPath
    }

    public convenience init(_ basePath: String) {
        self.init(using: basePath + ".pem", key: basePath + ".key")
    }

    public static func createSelfSignedIdentity(args: QUICServerIdentityCreationArgs) throws -> Self {
        let basePath = args.identityLabel
        let certPath = basePath + ".pem"
        let keyPath = basePath + ".key"

        if FileManager.default.fileExists(atPath: certPath) || FileManager.default.fileExists(atPath: keyPath) {
            throw QUICServerIdentityCreationError.fileAlreadyExists
        }

        let (certificate, privateKey) = try SelfSignedCertificateBuilder.createCertificateAndKey(args: args)

        if let passphrase = Self.keyPassphrase, !passphrase.isEmpty {
            // Passphrase-protected PKCS#8 not implemented yet
            throw QUICServerIdentityCreationError.notImplemented
        }

        // Export PEM
        let certPEM = try pemEncode(type: "CERTIFICATE") { serializer in
            try certificate.serialize(into: &serializer)
        }
        let keyPEM = pemEncode(type: "PRIVATE KEY", data: privateKey.derRepresentation)

        let certURL = URL(fileURLWithPath: certPath)
        let keyURL = URL(fileURLWithPath: keyPath)
        let dirURL = certURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true, attributes: nil)

        do {
            try certPEM.write(to: certURL, atomically: true, encoding: .utf8)
            try keyPEM.write(to: keyURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int(0o400))], ofItemAtPath: certPath)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int(0o400))], ofItemAtPath: keyPath)
        } catch {
            throw QUICServerIdentityCreationError.fileWriteFailed
        }

        return Self(using: certPath, key: keyPath)
    }

    public func getServerIdentity() async throws -> SecIdentity {
        guard FileManager.default.fileExists(atPath: certPath), FileManager.default.fileExists(atPath: keyPath) else {
            throw QUICServerIdentityCreationError.identityNotFound
        }

        let certData = try loadPEMData(atPath: certPath, type: "CERTIFICATE")
        let keyData = try loadPEMData(atPath: keyPath, type: "PRIVATE KEY")

        guard let secCertificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            throw QUICServerIdentityCreationError.certificateCreationFailed
        }

        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: 256
        ]
        var error: Unmanaged<CFError>?

        // SecKeyCreateWithData는 PKCS#8 DER을 직접 받지 못하므로, 우선 X9.63 형식으로 시도하고
        // 실패 시 PKCS#8을 CryptoKit으로 파싱해 X9.63으로 변환한 뒤 재시도한다.
        let secPrivateKey: SecKey?
        if let directKey = SecKeyCreateWithData(keyData as CFData, keyAttributes as CFDictionary, &error) {
            secPrivateKey = directKey
        } else if let parsed = try? P256.Signing.PrivateKey(derRepresentation: keyData) {
            error = nil
            let x963 = parsed.x963Representation
            secPrivateKey = SecKeyCreateWithData(x963 as CFData, keyAttributes as CFDictionary, &error)
        } else {
            secPrivateKey = nil
        }

        // FIXME: 신뢰 여부를 확인할 수 있었으면 좋겠는데..
        try SRSecurity.shared.trustCertificate(secCertificate, scope: .user).get()

        guard let secPrivateKey else {
            throw QUICServerIdentityCreationError.keychainLookupFailed(error?.takeRetainedValue().asOSStatus() ?? errSecInternalError)
        }

        guard let identity = SecIdentityCreate(nil, secCertificate, secPrivateKey) else {
            throw QUICServerIdentityCreationError.identityCreationFailed
        }

        return identity
    }
}

// MARK: - PEM helpers

func pemEncode(type: String, data: Data) -> String {
    let base64 = data.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
    return "-----BEGIN \(type)-----\n\(base64)\n-----END \(type)-----\n"
}

func pemEncode(type: String, serializer: (inout DER.Serializer) throws -> Void) throws -> String {
    var serializerInstance = DER.Serializer()
    try serializer(&serializerInstance)
    let der = Data(serializerInstance.serializedBytes)
    return pemEncode(type: type, data: der)
}

func loadPEMData(atPath path: String, type: String) throws -> Data {
    let pemString = try String(contentsOfFile: path, encoding: .utf8)
    guard let beginRange = pemString.range(of: "-----BEGIN \(type)-----"),
          let endRange = pemString.range(of: "-----END \(type)-----")
    else {
        throw QUICServerIdentityCreationError.identityNotFound
    }

    let body = pemString[beginRange.upperBound..<endRange.lowerBound]
    let stripped = body
        .replacingOccurrences(of: "\r", with: "")
        .replacingOccurrences(of: "\n", with: "")
        .replacingOccurrences(of: " ", with: "")

    guard let data = Data(base64Encoded: stripped) else {
        throw QUICServerIdentityCreationError.identityNotFound
    }

    return data
}
