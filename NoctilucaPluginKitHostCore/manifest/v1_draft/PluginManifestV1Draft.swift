//
//  PluginManifestV1Draft.swift
//  NoctilucaPluginKitHostCore
//
//  Created by Gyuhwan Park on 5/16/26.
//

import Foundation
@preconcurrency import NoctilucaPluginKit

// MARK: - PluginManifestV1Draft (NocPluginManifest decoding wrapper)

/// `NocPluginManifest` 의 v1-draft JSON 디코딩 wrapper.
///
/// JSON 의 `type` discriminator (auth_v1 / keyboard_hack_v1 / rpc_handler_v1) 를 보고
/// 해당 concrete struct 로 디코딩한 뒤 `NocPluginManifest` enum 으로 변환합니다.
public struct PluginManifestV1Draft: Codable, Sendable {
    public let manifest: NocPluginManifest

    public init(manifest: NocPluginManifest) {
        self.manifest = manifest
    }

    private enum DiscriminatorKey: String, CodingKey {
        case type
    }

    /// v1-draft 의 plugin `type` discriminator string.
    private enum PluginTypeTag: String {
        case auth_v1
        case keyboardHack_v1 = "keyboard_hack_v1"
        case rpcHandler_v1 = "rpc_handler_v1"
    }

    public init(from decoder: any Decoder) throws {
        let tagContainer = try decoder.container(keyedBy: DiscriminatorKey.self)
        let rawType = try tagContainer.decode(String.self, forKey: .type)

        guard let tag = PluginTypeTag(rawValue: rawType) else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: tagContainer,
                debugDescription: "Unknown plugin type discriminator '\(rawType)'"
            )
        }

        switch tag {
        case .auth_v1:
            let inner = try AuthPluginManifestV1Draft(from: decoder)
            self.manifest = .auth(inner)
        case .keyboardHack_v1:
            let inner = try KeyboardHackPluginManifestV1Draft(from: decoder)
            self.manifest = .keyboardHack(inner)
        case .rpcHandler_v1:
            let inner = try RPCHandlerPluginManifestV1Draft(from: decoder)
            self.manifest = .rpcHandler(inner)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        switch manifest {
        case .auth(let m):
            guard let concrete = m as? AuthPluginManifestV1Draft else {
                throw EncodingError.invalidValue(m, .init(
                    codingPath: encoder.codingPath,
                    debugDescription: "AuthPluginManifest is not a v1-draft instance"
                ))
            }
            try concrete.encode(to: encoder)
        case .keyboardHack(let m):
            guard let concrete = m as? KeyboardHackPluginManifestV1Draft else {
                throw EncodingError.invalidValue(m, .init(
                    codingPath: encoder.codingPath,
                    debugDescription: "KeyboardHackPluginManifest is not a v1-draft instance"
                ))
            }
            try concrete.encode(to: encoder)
        case .rpcHandler(let m):
            guard let concrete = m as? RPCHandlerPluginManifestV1Draft else {
                throw EncodingError.invalidValue(m, .init(
                    codingPath: encoder.codingPath,
                    debugDescription: "RPCHandlerPluginManifest is not a v1-draft instance"
                ))
            }
            try concrete.encode(to: encoder)
        }
    }
}

// MARK: - AuthPluginManifestV1Draft

public struct AuthPluginManifestV1Draft: AuthPluginManifest, Codable {
    public let id: String
    public let type: NoctilucaPluginType = .auth
    public let name: NocPluginLocalizableString
    public let pluginDescription: NocPluginLocalizableString
    public let authors: [String]
    public let license: SoftwareLicense
    public let version: UInt32
    public let displayVersion: String

    public let supportedMethods: [String]

    private enum CodingKeys: String, CodingKey {
        case id, type
        case name, description
        case authors, license, version, displayVersion
        case supportedMethods
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(NocPluginLocalizableString.self, forKey: .name)
        self.pluginDescription = try container.decode(NocPluginLocalizableString.self, forKey: .description)
        self.authors = try container.decode([String].self, forKey: .authors)
        self.license = try container.decode(SoftwareLicenseV1Draft.self, forKey: .license).resolved
        self.version = try container.decode(UInt32.self, forKey: .version)
        self.displayVersion = try container.decode(String.self, forKey: .displayVersion)
        self.supportedMethods = try container.decode([String].self, forKey: .supportedMethods)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode("auth_v1", forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encode(pluginDescription, forKey: .description)
        try container.encode(authors, forKey: .authors)
        try container.encode(SoftwareLicenseV1Draft(license), forKey: .license)
        try container.encode(version, forKey: .version)
        try container.encode(displayVersion, forKey: .displayVersion)
        try container.encode(supportedMethods, forKey: .supportedMethods)
    }
}

// MARK: - KeyboardHackPluginManifestV1Draft

public struct KeyboardHackPluginManifestV1Draft: KeyboardHackPluginManifest, Codable {
    public let id: String
    public let type: NoctilucaPluginType = .keyboardHack
    public let name: NocPluginLocalizableString
    public let pluginDescription: NocPluginLocalizableString
    public let authors: [String]
    public let license: SoftwareLicense
    public let version: UInt32
    public let displayVersion: String

    public let desiredKeyEvents: [String]

    private enum CodingKeys: String, CodingKey {
        case id, type
        case name, description
        case authors, license, version, displayVersion
        case desiredKeyEvents
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(NocPluginLocalizableString.self, forKey: .name)
        self.pluginDescription = try container.decode(NocPluginLocalizableString.self, forKey: .description)
        self.authors = try container.decode([String].self, forKey: .authors)
        self.license = try container.decode(SoftwareLicenseV1Draft.self, forKey: .license).resolved
        self.version = try container.decode(UInt32.self, forKey: .version)
        self.displayVersion = try container.decode(String.self, forKey: .displayVersion)
        self.desiredKeyEvents = try container.decode([String].self, forKey: .desiredKeyEvents)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode("keyboard_hack_v1", forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encode(pluginDescription, forKey: .description)
        try container.encode(authors, forKey: .authors)
        try container.encode(SoftwareLicenseV1Draft(license), forKey: .license)
        try container.encode(version, forKey: .version)
        try container.encode(displayVersion, forKey: .displayVersion)
        try container.encode(desiredKeyEvents, forKey: .desiredKeyEvents)
    }
}

// MARK: - RPCHandlerPluginManifestV1Draft

public struct RPCHandlerPluginManifestV1Draft: RPCHandlerPluginManifest, Codable {
    public let id: String
    public let type: NoctilucaPluginType = .rpcHandler
    public let name: NocPluginLocalizableString
    public let pluginDescription: NocPluginLocalizableString
    public let authors: [String]
    public let license: SoftwareLicense
    public let version: UInt32
    public let displayVersion: String

    public let supportedOperations: [String]

    private enum CodingKeys: String, CodingKey {
        case id, type
        case name, description
        case authors, license, version, displayVersion
        case supportedOperations
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(NocPluginLocalizableString.self, forKey: .name)
        self.pluginDescription = try container.decode(NocPluginLocalizableString.self, forKey: .description)
        self.authors = try container.decode([String].self, forKey: .authors)
        self.license = try container.decode(SoftwareLicenseV1Draft.self, forKey: .license).resolved
        self.version = try container.decode(UInt32.self, forKey: .version)
        self.displayVersion = try container.decode(String.self, forKey: .displayVersion)
        self.supportedOperations = try container.decode([String].self, forKey: .supportedOperations)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode("rpc_handler_v1", forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encode(pluginDescription, forKey: .description)
        try container.encode(authors, forKey: .authors)
        try container.encode(SoftwareLicenseV1Draft(license), forKey: .license)
        try container.encode(version, forKey: .version)
        try container.encode(displayVersion, forKey: .displayVersion)
        try container.encode(supportedOperations, forKey: .supportedOperations)
    }
}
