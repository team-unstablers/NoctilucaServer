//
//  SRKeychain.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Security

import CryptoKit

internal import SwiftASN1
internal import X509

public enum SRKeychainItemClass {
    case certificate
    case privateKey
    case identity

    public var secClass: CFString {
        switch self {
        case .certificate:
            return kSecClassCertificate
        case .privateKey:
            return kSecClassKey
        case .identity:
            return kSecClassIdentity
        }
    }

    public var typeId: CFTypeID {
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

public enum SRKeychainScope {
    /// 사용자별 키체인 (기본 키체인)
    case login
    /// System.keychain (시스템 전체)
    case system
    /// 임의의 경로에 있는 키체인
    case custom(String)
}

public enum SRKeychainError: LocalizedError {
    case itemNotFound

    case unexpectedStatus(OSStatus)
    case assertionFailed(reason: String)
    
    public var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "Keychain item not found."
        case .unexpectedStatus(let status):
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain operation failed with status \(status): \(message)"
            } else {
                return "Keychain operation failed with unknown status: \(status)"
            }
        case .assertionFailed(let reason):
            return "Assertion failed: \(reason)"
        }
    }
    
}

/// 'S'i'R'ius Keychain - macOS Security.framework의 Keychain 관련 기능을 wrap합니다.
public class SRKeychain {
    public static let shared = SRKeychain()

    // MARK: - Keychain Scope Helpers

#if os(macOS)
    private func resolveKeychain(for scope: SRKeychainScope) -> SecKeychain? {
        var keychain: SecKeychain?
        switch scope {
        case .login:
            SecKeychainCopyDomainDefault(.user, &keychain)
        case .system:
            SecKeychainCopyDomainDefault(.system, &keychain)
        case .custom(let path):
            SecKeychainOpen(path, &keychain)
        }
        return keychain
    }

    /// 조회/삭제 시 사용할 kSecMatchSearchList 엔트리
    private func searchScopeEntries(for scope: SRKeychainScope) -> [String: Any] {
        guard let keychain = resolveKeychain(for: scope) else { return [:] }
        return [kSecMatchSearchList as String: [keychain]]
    }

    /// 추가 시 사용할 kSecUseKeychain 엔트리
    private func addScopeEntries(for scope: SRKeychainScope) -> [String: Any] {
        guard let keychain = resolveKeychain(for: scope) else { return [:] }
        return [kSecUseKeychain as String: keychain]
    }
#else
    private func searchScopeEntries(for scope: SRKeychainScope) -> [String: Any] { [:] }
    private func addScopeEntries(for scope: SRKeychainScope) -> [String: Any] { [:] }
#endif

    // MARK: - Query

    /// 특정 라벨과 클래스에 해당하는 Keychain 아이템을 조회합니다.
    public func queryItem(by label: String, clazz: SRKeychainItemClass, scope: SRKeychainScope = .login, extras: [String: Any] = [:]) -> Result<CFTypeRef, SRKeychainError> {
        assert(clazz != .identity, "Use separate method for identity existence check.")

        let query: [String: Any] = searchScopeEntries(for: scope)
            .merging(extras, uniquingKeysWith: { (_, new) in new })
            .merging([
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

    public func queryItemExistance(by label: String, clazz: SRKeychainItemClass, scope: SRKeychainScope = .login, extras: [String: Any] = [:]) -> Result<Bool, SRKeychainError> {
        let queryResult = self.queryItem(by: label, clazz: clazz, scope: scope, extras: extras)

        switch queryResult {
        case .success:
            return .success(true)
        case .failure(let error):
            if case .itemNotFound = error {
                return .success(false)
            } else {
                return .failure(error)
            }
        }
    }

#if os(macOS)
    public func queryIdentity(by label: String, scope: SRKeychainScope = .login) -> Result<SecIdentity, SRKeychainError> {
        let certQueryResult = self.queryItem(by: label, clazz: .certificate, scope: scope)

        do {
            // swiftlint:disable:next force_cast
            let certificate = try certQueryResult.get() as! SecCertificate

            var identity: SecIdentity?
            let identityStatus = SecIdentityCreateWithCertificate(nil, certificate, &identity)

            guard identityStatus == errSecSuccess, let identity else {
                if identityStatus == errSecItemNotFound {
                    return .failure(.itemNotFound)
                }

                return .failure(.unexpectedStatus(identityStatus))
            }

            return .success(identity)
        } catch {
            return .failure(.itemNotFound)
        }
    }

    public func queryIdentityExistance(by label: String, scope: SRKeychainScope = .login) -> Result<Bool, SRKeychainError> {
        let identityResult = self.queryIdentity(by: label, scope: scope)

        switch identityResult {
        case .success:
            return .success(true)
        case .failure(let error):
            if case .itemNotFound = error {
                return .success(false)
            } else {
                return .failure(error)
            }
        }
    }
#endif

    // MARK: - Delete

    public func deleteItem(by label: String, clazz: SRKeychainItemClass, scope: SRKeychainScope = .login) -> Result<Void, SRKeychainError> {
        let query: [String: Any] = searchScopeEntries(for: scope).merging([
            kSecClass as String: clazz.secClass,
            kSecAttrLabel as String: label
        ], uniquingKeysWith: { (_, new) in new })

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            return .failure(.unexpectedStatus(status))
        }

        return .success(())
    }

    // MARK: - Add

    public func addItem(_ item: CFTypeRef, clazz: SRKeychainItemClass, label: String, scope: SRKeychainScope = .login, extras: [String: Any] = [:]) -> Result<Void, SRKeychainError> {
        let baseAttributes: [String: Any] = addScopeEntries(for: scope).merging([
            kSecClass as String: clazz.secClass,
            kSecAttrLabel as String: label,
            kSecValueRef as String: item,
            kSecAttrIsPermanent as String: true
        ], uniquingKeysWith: { (_, new) in new })

        let attributes = baseAttributes.merging(extras, uniquingKeysWith: { (_, new) in new })

        let status = SecItemAdd(attributes as CFDictionary, nil)

        guard status == errSecSuccess else {
            return .failure(.unexpectedStatus(status))
        }

        return .success(())
    }

    public func addTemporaryItem(_ item: CFTypeRef, clazz: SRKeychainItemClass, label: String, scope: SRKeychainScope = .login, extras: [String: Any] = [:]) -> Result<Void, SRKeychainError> {
        let extras: [String: Any] = extras.merging([
            kSecAttrIsPermanent as String: false
        ], uniquingKeysWith: { (_, new) in new })

        return self.addItem(item, clazz: clazz, label: label, scope: scope, extras: extras)
    }

    // MARK: - Secure Data (Generic Password)

    /// 설정 데이터(JSON 등)를 저장할 때 사용 (Generic Password 타입 전용)
    public func setSecureData(_ data: Data, key: String, scope: SRKeychainScope = .login) -> Result<Void, SRKeychainError> {
        // 1. 기존 데이터 삭제 (덮어쓰기 위해)
        let deleteQuery: [String: Any] = searchScopeEntries(for: scope).merging([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key
        ], uniquingKeysWith: { (_, new) in new })

        SecItemDelete(deleteQuery as CFDictionary)

        // 2. 데이터 추가
        let addQuery: [String: Any] = addScopeEntries(for: scope).merging([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key,
            kSecValueData as String: data
        ], uniquingKeysWith: { (_, new) in new })

        let status = SecItemAdd(addQuery as CFDictionary, nil)

        guard status == errSecSuccess else {
            return .failure(.unexpectedStatus(status))
        }

        return .success(())
    }

    /// 설정 데이터를 불러올 때 사용
    public func getSecureData(key: String, scope: SRKeychainScope = .login) -> Result<Data?, SRKeychainError> {
        let query: [String: Any] = searchScopeEntries(for: scope).merging([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key,
            kSecReturnData as String: true, // [중요] Ref가 아니라 Data를 달라고 해야 함
            kSecMatchLimit as String: kSecMatchLimitOne
        ], uniquingKeysWith: { (_, new) in new })

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return .success(nil) // 에러가 아니라 '없음'으로 처리
            }
            return .failure(.unexpectedStatus(status))
        }

        guard let data = item as? Data else {
            return .failure(.assertionFailed(reason: "Keychain item found but is not Data"))
        }

        return .success(data)
    }

    /// 데이터 삭제
    public func removeSecureData(key: String, scope: SRKeychainScope = .login) -> Result<Void, SRKeychainError> {
        let query: [String: Any] = searchScopeEntries(for: scope).merging([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key
        ], uniquingKeysWith: { (_, new) in new })

        let status = SecItemDelete(query as CFDictionary)

        if status == errSecSuccess || status == errSecItemNotFound {
            return .success(())
        }

        return .failure(.unexpectedStatus(status))
    }

}
