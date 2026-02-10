//
//  AppSettings.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/27/25.
//

import Foundation

import SiriusKitClient

struct AppSettings: Codable, Sendable {
    static let currentSchemaVersion: Int = 1

    // MARK: - Meta

    var schemaVersion: Int = Self.currentSchemaVersion

    // MARK: - General Settings

    var general: General = .init()

    // MARK: - Session Defaults

    var sessionDefaults: SessionSettings = SessionSettings(scope: .global)

    // MARK: - Input Settings

    var input: Input = .init()

    // MARK: - Security Settings

    var security: Security = .init()

    // MARK: - Misc Settings

    var misc: Misc = .init()
    var plugins: Plugins = .init()

    init() {}

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case general
        case sessionDefaults
        case input
        case security
        case misc
        case plugins
        case projection
    }

    init(from decoder: any Decoder) throws {
        self.init()

        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            return
        }

        let decodedSchemaVersion = container.decodeSafe(Int.self, forKey: .schemaVersion, default: 0)

        schemaVersion = decodedSchemaVersion == 0 ? Self.currentSchemaVersion : decodedSchemaVersion
        general = container.decodeSafe(General.self, forKey: .general, default: general)

        let decodedSessionDefaults = container.decodeSafeIfPresent(SessionSettings.self, forKey: .sessionDefaults)
        let sessionDefaultsMissing = decodedSessionDefaults == nil
        sessionDefaults = decodedSessionDefaults ?? SessionSettings(scope: .global)

        if let decodedInput = container.decodeSafeIfPresent(Input.self, forKey: .input) {
            input = decodedInput
        } else if let legacyInput = container.decodeSafeIfPresent(Input.self, forKey: .projection) {
            input = legacyInput
        }

        security = container.decodeSafe(Security.self, forKey: .security, default: security)
        misc = container.decodeSafe(Misc.self, forKey: .misc, default: misc)
        plugins = container.decodeSafe(Plugins.self, forKey: .plugins, default: plugins)

        migrateIfNeeded(from: decodedSchemaVersion, sessionDefaultsMissing: sessionDefaultsMissing)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(general, forKey: .general)
        try container.encode(sessionDefaults, forKey: .sessionDefaults)
        try container.encode(input, forKey: .input)
        try container.encode(security, forKey: .security)
        try container.encode(misc, forKey: .misc)
        try container.encode(plugins, forKey: .plugins)
    }

    mutating func migrateIfNeeded(from legacyVersion: Int, sessionDefaultsMissing: Bool = false) {
        if sessionDefaultsMissing, let legacy = Self.loadLegacySessionDefaults() {
            sessionDefaults = legacy
        }

        if legacyVersion < Self.currentSchemaVersion {
            schemaVersion = Self.currentSchemaVersion
        }

        normalizeSessionDefaults()
    }

    mutating func normalizeSessionDefaults() {
        sessionDefaults.scope = .global
        sessionDefaults.ensureCredentialsKey(scope: .global, contactId: nil)
    }
}

enum AppSettingsError: LocalizedError {
    case configNotFound
}

extension AppSettings {
    static let logger = NoctilucaLogger(category: "AppSettings")
    
    fileprivate static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        
        return encoder
    }()
    
    fileprivate static let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        
        return decoder
    }()
    
    protocol Category: Codable, Sendable {
        
    }
    
    protocol SecureCategory: Category {
        func saveSecureEntries() throws
        mutating func loadSecureEntries() throws
    }
    
    static func applicationSupportDirectory() throws -> URL {
        let fileManager = FileManager.default
        
        return try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent(NoctilucaMeta.bundleIdentifier, isDirectory: true)
    }
    
    private func savePublicConfig() throws {
        let fileManager = FileManager.default
        let applicationSupportDirectory = try Self.applicationSupportDirectory()
        
        var sanitized = self

        let json = try Self.jsonEncoder.encode(sanitized)
        
        let settingsURL = applicationSupportDirectory.appendingPathComponent("settings.json", isDirectory: false)
        
        if !fileManager.fileExists(atPath: applicationSupportDirectory.path) {
            try fileManager.createDirectory(
                at: applicationSupportDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }
        
        try json.write(to: settingsURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: settingsURL.path
        )
    }
    
    private func saveSecureConfig() throws {
        try security.saveSecureEntries()
    }
    
    func save() throws {
        try saveSecureConfig()
        try savePublicConfig()
    }
    
    private static func loadPublicConfig() throws -> AppSettings {
        let fileManager = FileManager.default
        let applicationSupportDirectory = try Self.applicationSupportDirectory()
        
        let settingsURL = applicationSupportDirectory.appendingPathComponent("settings.json", isDirectory: false)
        
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            throw AppSettingsError.configNotFound
        }

        let settings = try Self.jsonDecoder.decode(
            AppSettings.self,
            from: try Data(contentsOf: settingsURL),
        )
        
        return consume settings
    }
    
    private mutating func loadSecureConfig() throws {
        try security.loadSecureEntries()
    }
    
    static func load() throws -> AppSettings {
        do {
            logger.debug("Loading public configuration...")
            var settings = try loadPublicConfig()
            
            logger.debug("Loading secure configuration...")
            try settings.loadSecureConfig()
            
            logger.info("Configuration loaded successfully.")
            return consume settings
        } catch {
            logger.error("Failed to load AppSettings: \(error.localizedDescription), using default settings instead.")
            var fallback = AppSettings()
            if let legacy = loadLegacySessionDefaults() {
                fallback.sessionDefaults = legacy
                fallback.normalizeSessionDefaults()
            }
            return fallback
        }
    }
}

private extension AppSettings {
    static func legacySessionSettingsURL() throws -> URL {
        let directory = try applicationSupportDirectory()
        return directory.appendingPathComponent("session-settings.json", isDirectory: false)
    }

    static func loadLegacySessionDefaults() -> SessionSettings? {
        let fileManager = FileManager.default
        guard let settingsURL = try? legacySessionSettingsURL(),
              fileManager.fileExists(atPath: settingsURL.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: settingsURL),
              var settings = try? jsonDecoder.decode(SessionSettings.self, from: data) else {
            return nil
        }

        settings.scope = .global
        settings.ensureCredentialsKey(scope: .global, contactId: nil)
        
        return settings
    }
}

extension AppSettings.SecureCategory {
    func saveSecureEntry(_ entry: Codable, forKey key: String) throws {
        let keychain = SRKeychain.shared
        let data = try AppSettings.jsonEncoder.encode(entry)
        
        _ = try keychain.setSecureData(consume data, key: key).get()
    }
    
    func loadSecureEntry<T: Codable>(forKey key: String, as type: T.Type) throws -> T? {
        let keychain = SRKeychain.shared
        
        guard let data = try keychain.getSecureData(key: key).get() else {
            return nil
        }
        
        return try JSONDecoder().decode(type, from: consume data)
    }
    
    func removeSecureEntry(forKey key: String) throws {
        let keychain = SRKeychain.shared
        
        _ = try keychain.removeSecureData(key: key).get()
    }
}

extension KeyedDecodingContainer {
    func decodeSafe<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: @autoclosure () -> T) -> T {
        return (try? decodeIfPresent(type, forKey: key)) ?? defaultValue()
    }

    func decodeSafeIfPresent<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        return (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}
