//
//  SessionSettingsStore.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation
import Combine
import SwiftUI

import SiriusKitClient

@MainActor
final class SessionSettingsStore: ObservableObject {
    private static let logger = NoctilucaLogger(category: "SessionSettingsStore")
    private static let fileName = "session-settings.json"

    @Published
    var global: SessionSettings

    @Published
    var session: SessionSettings

    @Published
    var currentContactId: UUID? = nil {
        didSet {
            if let contactId = currentContactId {
                session.credentials.keychainKey = credentialsKey(for: .session, contactId: contactId)
            } else {
                session.credentials.keychainKey = nil
            }
        }
    }

    private var cancellables: Set<AnyCancellable> = []

    init(loadFromDisk: Bool = true) {
        if loadFromDisk {
            global = (try? Self.loadGlobal()) ?? SessionSettings(scope: .global)
        } else {
            global = SessionSettings(scope: .global)
        }

        session = SessionSettings(scope: .session)
        ensureGlobalCredentialsKey()
        setupAutosave()
    }

    func binding<T>(for scope: SessionSettingsScope, keyPath: WritableKeyPath<SessionSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings(for: scope)[keyPath: keyPath] },
            set: { newValue in
                self.updateSettings(for: scope) { settings in
                    settings[keyPath: keyPath] = newValue
                }
            }
        )
    }

    func settings(for scope: SessionSettingsScope) -> SessionSettings {
        switch scope {
        case .global:
            return global
        case .session:
            return session
        }
    }

    func updateSettings(for scope: SessionSettingsScope, _ update: (inout SessionSettings) -> Void) {
        switch scope {
        case .global:
            update(&global)
        case .session:
            update(&session)
        }
    }

    func saveGlobal() {
        do {
            try Self.saveGlobal(global)
        } catch {
            Self.logger.error("Failed to save session settings: \(error.localizedDescription)")
        }
    }

    func reloadGlobal() {
        global = (try? Self.loadGlobal()) ?? SessionSettings(scope: .global)
        ensureGlobalCredentialsKey()
    }

    func credentialsKey(for scope: SessionSettingsScope, contactId: UUID? = nil) -> String? {
        SessionSettings.credentialsKey(for: scope, contactId: contactId)
    }

    func loadCredentials(for scope: SessionSettingsScope, contactId: UUID? = nil) -> [ClientAuthEntry] {
        guard let key = credentialsKey(for: scope, contactId: contactId) else { return [] }
        let keychain = SRKeychain.shared

        guard let stored = try? keychain.getSecureData(key: key).get(),
              let data = stored else {
            return []
        }

        return (try? Self.jsonDecoder.decode([ClientAuthEntry].self, from: data)) ?? []
    }

    @discardableResult
    func saveCredentials(_ entries: [ClientAuthEntry], for scope: SessionSettingsScope, contactId: UUID? = nil) -> SessionSettings.CredentialsRef {
        guard let key = credentialsKey(for: scope, contactId: contactId) else {
            return SessionSettings.CredentialsRef()
        }

        let keychain = SRKeychain.shared
        do {
            let data = try Self.jsonEncoder.encode(entries)
            _ = try keychain.setSecureData(consume data, key: key).get()
        } catch {
            Self.logger.error("Failed to save credentials: \(error.localizedDescription)")
        }

        let ref = SessionSettings.CredentialsRef(keychainKey: key, lastUpdatedAt: Date())
        if scope == .global {
            global.credentials = ref
        } else if scope == .session, contactId == currentContactId {
            session.credentials = ref
        }
        return ref
    }

    func removeCredentials(for scope: SessionSettingsScope, contactId: UUID? = nil) {
        guard let key = credentialsKey(for: scope, contactId: contactId) else { return }
        let keychain = SRKeychain.shared
        _ = try? keychain.removeSecureData(key: key).get()
        if scope == .global {
            global.credentials = .init()
        } else if scope == .session, contactId == currentContactId {
            session.credentials = .init()
        }
    }

    func credentialsCount(for scope: SessionSettingsScope, contactId: UUID? = nil) -> Int {
        loadCredentials(for: scope, contactId: contactId).count
    }

    private func setupAutosave() {
        $global
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.saveGlobal()
            }
            .store(in: &cancellables)
    }

    private func ensureGlobalCredentialsKey() {
        if global.scope != .global {
            global.scope = .global
        }
        if global.credentials.keychainKey == nil {
            global.credentials.keychainKey = credentialsKey(for: .global, contactId: nil)
        }
    }
}

private extension SessionSettingsStore {
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

    static func settingsURL() throws -> URL {
        let directory = try AppSettings.applicationSupportDirectory()
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }

    static func saveGlobal(_ settings: SessionSettings) throws {
        let fileManager = FileManager.default
        let settingsURL = try settingsURL()

        var sanitized = settings
        if sanitized.security.knownHost?.trust == .trustOnce {
            sanitized.security.knownHost = nil
        }

        let json = try jsonEncoder.encode(sanitized)

        if !fileManager.fileExists(atPath: settingsURL.deletingLastPathComponent().path) {
            try fileManager.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        try json.write(to: settingsURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)
    }

    static func loadGlobal() throws -> SessionSettings {
        let fileManager = FileManager.default
        let settingsURL = try settingsURL()
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            throw AppSettingsError.configNotFound
        }

        return try jsonDecoder.decode(SessionSettings.self, from: Data(contentsOf: settingsURL))
    }
}
