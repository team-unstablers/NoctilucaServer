//
//  KeychainQUICServerIdentity.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Security

public class KeychainQUICServerIdentity: QUICServerIdentity {
    private let identityLabel: String
    
    public required init(_ identityLabel: String) {
        self.identityLabel = identityLabel
    }
    
    public static func createSelfSignedIdentity(args: QUICServerIdentityCreationArgs) throws -> Self {
        /*
        // 충돌 여부 확인
        if identityExists(label: args.identityLabel) {
            throw QUICServerIdentityCreationError.identityAlreadyExists
        }
        
        // 키체인에 보관되는 self-signed 인증서 생성
        let (_, certificate) = try SelfSignedCertificateBuilder.createIdentity(args: args, storePrivateKeyInKeychain: true)
        
        // 인증서를 키체인에 저장 (키는 isPermanent로 생성)
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: args.identityLabel
        ]
        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            // best-effort cleanup of generated key on failure
            deletePrivateKey(label: args.identityLabel)
            
            if status == errSecDuplicateItem {
                throw QUICServerIdentityCreationError.identityAlreadyExists
            }
            throw QUICServerIdentityCreationError.keychainWriteFailed(status)
        }
        
        return Self(args.identityLabel)
         */
        
        throw QUICServerIdentityCreationError.notImplemented
    }
    
    public func getServerIdentity() async throws -> sec_identity_t {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: self.identityLabel,
            kSecReturnRef as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status != errSecItemNotFound else {
            throw QUICServerIdentityCreationError.identityNotFound
        }
        guard status == errSecSuccess, let item else {
            throw QUICServerIdentityCreationError.keychainLookupFailed(status)
        }
        
        let identityCF = item as CFTypeRef
        guard CFGetTypeID(identityCF) == SecIdentityGetTypeID() else {
            throw QUICServerIdentityCreationError.keychainLookupFailed(errSecParam)
        }
        
        let identity = unsafeBitCast(identityCF, to: sec_identity_t.self)
        return identity
    }
    
    private static func identityExists(label: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: label,
            kSecReturnRef as String: true
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    private static func deletePrivateKey(label: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrLabel as String: label
        ]
        SecItemDelete(query as CFDictionary)
    }
}
