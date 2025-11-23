//
//  P12FileQUICServerIdentity.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Security

import SwiftASN1
import X509

public class P12FileQUICServerIdentity: QUICServerIdentity {
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
    
    public func getServerIdentity() async throws -> sec_identity_t {
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
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrIsPermanent as String: false
        ]
        var error: Unmanaged<CFError>?
        guard let secPrivateKey = SecKeyCreateWithData(keyData as CFData, keyAttributes as CFDictionary, &error) else {
            throw QUICServerIdentityCreationError.keychainLookupFailed(error?.takeRetainedValue().asOSStatus() ?? errSecInternalError)
        }
        
        guard let identity = SecIdentityCreate(nil, secCertificate, secPrivateKey) else {
            throw QUICServerIdentityCreationError.identityCreationFailed
        }
        
        return unsafeBitCast(identity, to: sec_identity_t.self)
    }
}

// MARK: - PEM helpers

private func pemEncode(type: String, data: Data) -> String {
    let base64 = data.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
    return "-----BEGIN \(type)-----\n\(base64)\n-----END \(type)-----\n"
}

private func pemEncode(type: String, serializer: (inout DER.Serializer) throws -> Void) throws -> String {
    var serializerInstance = DER.Serializer()
    try serializer(&serializerInstance)
    let der = Data(serializerInstance.serializedBytes)
    return pemEncode(type: type, data: der)
}

private func loadPEMData(atPath path: String, type: String) throws -> Data {
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
