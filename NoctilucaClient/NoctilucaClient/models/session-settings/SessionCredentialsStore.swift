//
//  SessionCredentialsStore.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

import SiriusKitClient

struct SessionCredentialsStore {
    private static let logger = NoctilucaLogger(category: "SessionCredentialsStore")

    static func load(
        scope: SessionSettingsScope,
        contactId: UUID?,
        keyOverride: String? = nil
    ) -> [ClientAuthEntry] {
        guard let key = resolveKey(scope: scope, contactId: contactId, keyOverride: keyOverride) else {
            return []
        }

        let keychain = SRKeychain.shared
        guard let stored = try? keychain.getSecureData(key: key).get(),
              let data = stored else {
            return []
        }

        return (try? jsonDecoder.decode([ClientAuthEntry].self, from: data)) ?? []
    }

    @discardableResult
    static func save(
        _ entries: [ClientAuthEntry],
        scope: SessionSettingsScope,
        contactId: UUID?,
        currentRef: SessionSettings.CredentialsRef
    ) -> SessionSettings.CredentialsRef {
        guard let key = resolveKey(scope: scope, contactId: contactId, keyOverride: currentRef.keychainKey) else {
            return SessionSettings.CredentialsRef()
        }

        let keychain = SRKeychain.shared
        do {
            let data = try jsonEncoder.encode(entries)
            _ = try keychain.setSecureData(consume data, key: key).get()
        } catch {
            logger.error("Failed to save credentials: \(error.localizedDescription)")
        }

        return SessionSettings.CredentialsRef(keychainKey: key, lastUpdatedAt: Date())
    }

    static func remove(
        scope: SessionSettingsScope,
        contactId: UUID?,
        currentRef: SessionSettings.CredentialsRef
    ) -> SessionSettings.CredentialsRef {
        guard let key = resolveKey(scope: scope, contactId: contactId, keyOverride: currentRef.keychainKey) else {
            return SessionSettings.CredentialsRef()
        }

        let keychain = SRKeychain.shared
        _ = try? keychain.removeSecureData(key: key).get()
        return SessionSettings.CredentialsRef()
    }

    private static func resolveKey(scope: SessionSettingsScope, contactId: UUID?, keyOverride: String?) -> String? {
        if let keyOverride {
            return keyOverride
        }
        return SessionSettings.credentialsKey(for: scope, contactId: contactId)
    }
}

private extension SessionCredentialsStore {
    static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }()

    static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        return decoder
    }()
}
