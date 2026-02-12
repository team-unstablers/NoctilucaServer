//
//  PEMFileQUICServerIdentity.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Security
import CryptoKit
import _CryptoExtras

internal import SwiftASN1
internal import X509
import SiriusKitCore

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

        let certDataList = try loadPEMDatas(atPath: certPath, type: "CERTIFICATE")
        guard let certData = certDataList.first else {
            throw QUICServerIdentityCreationError.identityNotFound
        }

        let (privateKey, keyType) = try loadPrivateKeyFromPEM(atPath: keyPath)

        guard let secCertificate = SecCertificateCreateWithData(nil, certData as CFData) else {
            throw QUICServerIdentityCreationError.certificateCreationFailed
        }

        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: keyType.secKeyType,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: keyType.keySizeInBits
        ]
        var error: Unmanaged<CFError>?

        let secPrivateKey: SecKey?
        switch privateKey {
        case .p256(let key):
            let x963 = key.x963Representation
            secPrivateKey = SecKeyCreateWithData(x963 as CFData, keyAttributes as CFDictionary, &error)
        case .rsa(let key):
            secPrivateKey = SecKeyCreateWithData(key.derRepresentation as CFData, keyAttributes as CFDictionary, &error)
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

    public func getCertificateChain() async throws -> [SecCertificate] {
        guard FileManager.default.fileExists(atPath: certPath) else {
            throw QUICServerIdentityCreationError.identityNotFound
        }

        let certDataList = try loadPEMDatas(atPath: certPath, type: "CERTIFICATE")
        guard certDataList.count > 1 else {
            return []
        }

        var chain: [SecCertificate] = []
        for certData in certDataList.dropFirst() {
            guard let secCertificate = SecCertificateCreateWithData(nil, certData as CFData) else {
                throw QUICServerIdentityCreationError.certificateCreationFailed
            }
            chain.append(secCertificate)
        }

        return chain
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
    let pemDataList = try loadPEMDatas(atPath: path, type: type)
    guard let firstPEMData = pemDataList.first else {
        throw QUICServerIdentityCreationError.identityNotFound
    }

    return firstPEMData
}

func loadPEMDatas(atPath path: String, type: String) throws -> [Data] {
    let pemString = try String(contentsOfFile: path, encoding: .utf8)
    guard let pemDataList = extractAllPEMData(from: pemString, type: type), !pemDataList.isEmpty else {
        throw QUICServerIdentityCreationError.identityNotFound
    }

    return pemDataList
}

func loadPrivateKeyFromPEM(atPath path: String) throws -> (IdentityPrivateKey, IdentityKeyType) {
    let pemString = try String(contentsOfFile: path, encoding: .utf8)

    if let data = extractPEMData(from: pemString, type: "PRIVATE KEY") {
        let key = try PKCS8Parser.parse(data)
        return (key, try identityKeyType(for: key))
    }

    if let data = extractPEMData(from: pemString, type: "RSA PRIVATE KEY") {
        let rsaKey = try _RSA.Signing.PrivateKey(derRepresentation: data)
        let key = IdentityPrivateKey.rsa(rsaKey)
        return (key, try identityKeyType(for: key))
    }

    if let data = extractPEMData(from: pemString, type: "EC PRIVATE KEY") {
        let ecKey = try P256.Signing.PrivateKey(derRepresentation: data)
        return (.p256(ecKey), .p256)
    }

    throw QUICServerIdentityCreationError.identityNotFound
}

private func identityKeyType(for key: IdentityPrivateKey) throws -> IdentityKeyType {
    switch key {
    case .p256:
        return .p256
    case .rsa(let rsaKey):
        switch rsaKey.keySizeInBits {
        case 2048:
            return .rsa2048
        case 4096:
            return .rsa4096
        default:
            throw PKCS8ParseError.unsupportedAlgorithm
        }
    }
}

private func extractPEMData(from pemString: String, type: String) -> Data? {
    return extractAllPEMData(from: pemString, type: type)?.first
}

private func extractAllPEMData(from pemString: String, type: String) -> [Data]? {
    let beginMarker = "-----BEGIN \(type)-----"
    let endMarker = "-----END \(type)-----"

    var searchRange = pemString.startIndex..<pemString.endIndex
    var results: [Data] = []

    while let beginRange = pemString.range(of: beginMarker, range: searchRange),
          let endRange = pemString.range(of: endMarker, range: beginRange.upperBound..<pemString.endIndex)
    {
        let body = pemString[beginRange.upperBound..<endRange.lowerBound]
        let stripped = body
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")

        guard let decoded = Data(base64Encoded: stripped) else {
            return nil
        }

        results.append(decoded)
        searchRange = endRange.upperBound..<pemString.endIndex
    }

    return results.isEmpty ? nil : results
}
