//
//  SRKeychain.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Security

import CryptoKit

import SwiftASN1
import X509

enum SRKeychainItemClass {
    case certificate
    case privateKey
    case identity
    
    var secClass: CFString {
        switch self {
        case .certificate:
            return kSecClassCertificate
        case .privateKey:
            return kSecClassKey
        case .identity:
            return kSecClassIdentity
        }
    }
    
    var typeId: CFTypeID {
        switch self {
        case .certificate:
            return SecCertificateGetTypeID()
        case .privateKey:
            return SecKeyGetTypeID()
        case .identity:
            return SecIdentityGetTypeID()
        }
    }
}

enum SRKeychainError: Error {
    case itemNotFound
    
    case unexpectedStatus(OSStatus)
    case assertionFailed(reason: String)
}

/// 'S'i'R'ius Keychain - macOS Security.framework의 Keychain 관련 기능을 wrap합니다.
class SRKeychain {
    public static let shared = SRKeychain()
    
    /// 특정 라벨과 클래스에 해당하는 Keychain 아이템을 조회합니다.
    func queryItem(by label: String, clazz: SRKeychainItemClass, extras: [String: Any] = [:]) -> Result<CFTypeRef, SRKeychainError> {
        assert(clazz != .identity, "Use separate method for identity existence check.")
        
        let query: [String: Any] = extras.merging([
            kSecClass as String: clazz.secClass,
            kSecAttrLabel as String: label,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnRef as String: true
        ], uniquingKeysWith: { (_, new) in new })
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        guard status == errSecSuccess, let foundItem = item else {
            if status == errSecItemNotFound {
                return .failure(.itemNotFound)
            } else {
                return .failure(.unexpectedStatus(status))
            }
        }
        
        guard CFGetTypeID(foundItem) == clazz.typeId else {
            return .failure(.assertionFailed(reason: "query item success but type mismatch (expected: \(clazz.typeId), found: \(CFGetTypeID(foundItem)))"))
        }
        
        return .success(foundItem)
    }
    
    func queryItemExistance(by label: String, clazz: SRKeychainItemClass, extras: [String: Any] = [:]) -> Result<Bool, SRKeychainError> {
        let queryResult = self.queryItem(by: label, clazz: clazz, extras: extras)
        
        switch queryResult {
        case .success(_):
            return .success(true)
        case .failure(let error):
            if case .itemNotFound = error {
                return .success(false)
            } else {
                return .failure(error)
            }
        }
    }

    func queryIdentity(by label: String) -> Result<SecIdentity, SRKeychainError> {
        let certQueryResult = self.queryItem(by: label, clazz: .certificate)
        
        if case .failure(let error) = certQueryResult {
            return .failure(error)
        }
        
        let certificate = try! certQueryResult.get() as! SecCertificate
       
        var identity: SecIdentity?
        let identityStatus = SecIdentityCreateWithCertificate(nil, certificate, &identity)
        
        guard identityStatus == errSecSuccess, let identity else {
            if identityStatus == errSecItemNotFound {
                return .failure(.itemNotFound)
            }
            
            return .failure(.unexpectedStatus(identityStatus))
        }
        
        return .success(identity)
    }
    
    func queryIdentityExistance(by label: String) -> Result<Bool, SRKeychainError> {
        let identityResult = self.queryIdentity(by: label)
        
        switch identityResult {
        case .success(_):
            return .success(true)
        case .failure(let error):
            if case .itemNotFound = error {
                return .success(false)
            } else {
                return .failure(error)
            }
        }
    }
    
    func deleteItem(by label: String, clazz: SRKeychainItemClass) -> Result<Void, SRKeychainError> {
        let query: [String: Any] = [
            kSecClass as String: clazz.secClass,
            kSecAttrLabel as String: label
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            return .failure(.unexpectedStatus(status))
        }
        
        return .success(())
    }
    
    func addItem(_ item: CFTypeRef, clazz: SRKeychainItemClass, label: String, extras: [String: Any] = [:]) -> Result<Void, SRKeychainError> {
        let baseAttributes: [String: Any] = [
            kSecClass as String: clazz.secClass,
            kSecAttrLabel as String: label,
            kSecValueRef as String: item,
            kSecAttrIsPermanent as String: true
        ]
        
        let attributes = baseAttributes.merging(extras, uniquingKeysWith: { (_, new) in new })
        
        let status = SecItemAdd(attributes as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            return .failure(.unexpectedStatus(status))
        }
        
        return .success(())
    }
    
    func addTemporaryItem(_ item: CFTypeRef, clazz: SRKeychainItemClass, label: String, extras: [String: Any] = [:]) -> Result<Void, SRKeychainError> {
        let extras: [String: Any] = extras.merging([
            kSecAttrIsPermanent as String: false
        ], uniquingKeysWith: { (_, new) in new })
        
        return self.addItem(item, clazz: clazz, label: label, extras: extras)
    }
    
}
