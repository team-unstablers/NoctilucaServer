//
//  P12FileQUICServerIdentity.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Security

public class P12QUICServerIdentity: QUICServerIdentity {
    private let path: String
    private let passphrase = ""
    
    public required init(_ path: String) {
        self.path = path
    }
    
    public static func createSelfSignedIdentity(args: QUICServerIdentityCreationArgs) throws -> Self {
        /*
        let path = args.identityLabel
        
        if FileManager.default.fileExists(atPath: path) {
            throw QUICServerIdentityCreationError.fileAlreadyExists
        }
        
        let (identity, _) = try SelfSignedCertificateBuilder.createIdentity(args: args, storePrivateKeyInKeychain: false)
        
        // Export to PKCS#12 with empty passphrase
        var exportParams = SecItemImportExportKeyParameters()
        exportParams.version = UInt32(SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION)
        exportParams.passphrase = "" as CFTypeRef
        var p12DataRef: CFData?
        let exportStatus = withUnsafePointer(to: &exportParams) { paramsPtr in
            SecItemExport(identity, .formatPKCS12, [], paramsPtr, &p12DataRef)
        }
        guard exportStatus == errSecSuccess, let p12Data = p12DataRef as Data? else {
            throw QUICServerIdentityCreationError.pkcs12ExportFailed(exportStatus)
        }
        
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        do {
            try p12Data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: Int(0o400))], ofItemAtPath: path)
        } catch {
            throw QUICServerIdentityCreationError.fileWriteFailed
        }
        
        return Self(args.identityLabel)
         */
        
        throw QUICServerIdentityCreationError.notImplemented
    }
    
    public func getServerIdentity() async throws -> sec_identity_t {
        let path = self.path
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        
        var importResult: CFArray?
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: passphrase
        ]
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &importResult)
        guard status == errSecSuccess else {
            throw QUICServerIdentityCreationError.pkcs12ImportFailed(status)
        }
        guard
            let items = importResult as? [[String: Any]],
            let first = items.first,
            let identityRef = first[kSecImportItemIdentity as String]
        else {
            throw QUICServerIdentityCreationError.identityNotFound
        }
        
        let identityCF = identityRef as CFTypeRef
        guard CFGetTypeID(identityCF) == SecIdentityGetTypeID() else {
            throw QUICServerIdentityCreationError.pkcs12ImportFailed(errSecParam)
        }
        
        let identity = unsafeBitCast(identityCF, to: sec_identity_t.self)
        return identity
    }
}
