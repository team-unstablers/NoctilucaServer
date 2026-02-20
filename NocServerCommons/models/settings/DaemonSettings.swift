//
//  AppSettings.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/27/25.
//

import Foundation

import SiriusKit

struct DaemonSettings: Codable, Sendable {
    // MARK: - General Settings
    
    var general: General = .init()
    
    // MARK: - Security Settings
    
    var security: Security = .init()
    var transport: Transport = .init()
    var quicTransport: QUICTransport = .init()
    
    // MARK: - Misc Settings

    var logging: Logging = .init()
    var telemetry: Telemetry = .init()

    init() {}

    enum CodingKeys: String, CodingKey {
        case general
        case security
        case transport
        case quicTransport
        case logging
        case telemetry
    }

    init(from decoder: any Decoder) throws {
        self.init()

        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            return
        }

        general = container.decodeSafe(General.self, forKey: .general, default: general)
        security = container.decodeSafe(Security.self, forKey: .security, default: security)
        transport = container.decodeSafe(Transport.self, forKey: .transport, default: transport)
        quicTransport = container.decodeSafe(QUICTransport.self, forKey: .quicTransport, default: quicTransport)
        logging = container.decodeSafe(Logging.self, forKey: .logging, default: logging)
        telemetry = container.decodeSafe(Telemetry.self, forKey: .telemetry, default: telemetry)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(general, forKey: .general)
        try container.encode(security, forKey: .security)
        try container.encode(transport, forKey: .transport)
        try container.encode(quicTransport, forKey: .quicTransport)
        try container.encode(logging, forKey: .logging)
        try container.encode(telemetry, forKey: .telemetry)
    }
}

enum DaemonSettingsError: LocalizedError {
    case configNotFound
}

extension DaemonSettings {
    static let logger = NoctilucaLogger(category: "DaemonSettings")
    
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
#if NOC_DAEMON
        func saveSecureEntries(scope: DaemonScope) throws
        mutating func loadSecureEntries(scope: DaemonScope) throws
#endif
    }
    
#if NOC_DAEMON
    static func applicationSupportDirectory(scope: DaemonScope) throws -> URL {
        let fileManager = FileManager.default
        
        return try fileManager.url(
            for: .applicationSupportDirectory,
            in: scope == .global ? .systemDomainMask : .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent(NoctilucaMeta.bundleIdentifier, isDirectory: true)
    }
    
    private func savePublicConfig(scope: DaemonScope) throws {
        let fileManager = FileManager.default
        let applicationSupportDirectory = try Self.applicationSupportDirectory(scope: scope)
        
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
    
    private func saveSecureConfig(scope: DaemonScope) throws {
        try security.saveSecureEntries(scope: scope)
    }
    
    func save(scope: DaemonScope) throws {
        try saveSecureConfig(scope: scope)
        try savePublicConfig(scope: scope)
    }
    
    private static func loadPublicConfig(scope: DaemonScope) throws -> DaemonSettings {
        let fileManager = FileManager.default
        let applicationSupportDirectory = try Self.applicationSupportDirectory(scope: scope)
        
        let settingsURL = applicationSupportDirectory.appendingPathComponent("settings.json", isDirectory: false)
        
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            throw DaemonSettingsError.configNotFound
        }

        let settings = try Self.jsonDecoder.decode(
            DaemonSettings.self,
            from: try Data(contentsOf: settingsURL),
        )
        
        return consume settings
    }
    
    private mutating func loadSecureConfig(scope: DaemonScope) throws {
        try security.loadSecureEntries(scope: scope)
    }
    
    static func load(scope: DaemonScope) throws -> DaemonSettings {
        do {
            logger.debug("Loading public configuration...")
            var settings = try loadPublicConfig(scope: scope)
            
            logger.debug("Loading secure configuration...")
            try settings.loadSecureConfig(scope: scope)
            
            logger.info("Configuration loaded successfully.")
            return consume settings
        } catch {
            logger.error("Failed to load AppSettings: \(error.localizedDescription), using default settings instead.")
            return DaemonSettings()
        }
    }
#endif
}

#if NOC_DAEMON
extension DaemonSettings.SecureCategory {
    func saveSecureEntry(_ entry: Codable, forKey key: String, scope: DaemonScope) throws {
        let keychain = SRKeychain.shared
        let data = try DaemonSettings.jsonEncoder.encode(entry)
        
        _ = try keychain.setSecureData(consume data, key: key, scope: scope == .global ? .system : .login).get()
    }
    
    func loadSecureEntry<T: Codable>(forKey key: String, as type: T.Type, scope: DaemonScope) throws -> T? {
        let keychain = SRKeychain.shared
        
        guard let data = try keychain.getSecureData(key: key, scope: scope == .global ? .system : .login).get() else {
            return nil
        }
        
        return try JSONDecoder().decode(type, from: consume data)
    }
    
    func removeSecureEntry(forKey key: String, scope: DaemonScope) throws {
        let keychain = SRKeychain.shared
        
        _ = try keychain.removeSecureData(key: key, scope: scope == .global ? .system : .login).get()
    }
}
#endif

extension KeyedDecodingContainer {
    func decodeSafe<T: Decodable>(_ type: T.Type, forKey key: Key, default defaultValue: @autoclosure () -> T) -> T {
        return (try? decodeIfPresent(type, forKey: key)) ?? defaultValue()
    }
}
