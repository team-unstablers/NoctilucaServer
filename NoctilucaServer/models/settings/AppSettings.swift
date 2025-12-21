//
//  AppSettings.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/27/25.
//

import Foundation

import SiriusKit

struct AppSettings: Codable, Sendable {
    // MARK: - General Settings
    
    var general: General = .init()
    var notifications: Notifications = .init()
    
    // MARK: - Projection Settings
    var projection: Projection = .init()
    
    // MARK: - Security Settings
    
    var security: Security = .init()
    var transport: Transport = .init()
    var quicTransport: QUICTransport = .init()
    
    // MARK: - Misc Settings
    
    var telemetry: Telemetry = .init()

    init() {}

    enum CodingKeys: String, CodingKey {
        case general
        case notifications
        case projection
        case security
        case transport
        case quicTransport
        case telemetry
    }

    init(from decoder: any Decoder) throws {
        self.init()

        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            return
        }

        general = container.decodeSafe(General.self, forKey: .general, default: general)
        notifications = container.decodeSafe(Notifications.self, forKey: .notifications, default: notifications)
        projection = container.decodeSafe(Projection.self, forKey: .projection, default: projection)
        security = container.decodeSafe(Security.self, forKey: .security, default: security)
        transport = container.decodeSafe(Transport.self, forKey: .transport, default: transport)
        quicTransport = container.decodeSafe(QUICTransport.self, forKey: .quicTransport, default: quicTransport)
        telemetry = container.decodeSafe(Telemetry.self, forKey: .telemetry, default: telemetry)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(general, forKey: .general)
        try container.encode(notifications, forKey: .notifications)
        try container.encode(projection, forKey: .projection)
        try container.encode(security, forKey: .security)
        try container.encode(transport, forKey: .transport)
        try container.encode(quicTransport, forKey: .quicTransport)
        try container.encode(telemetry, forKey: .telemetry)
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
        
        let json = try Self.jsonEncoder.encode(self)
        
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
            return AppSettings()
        }
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
}
