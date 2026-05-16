//
//  PluginManifestV1Draft.swift
//  NoctilucaServer
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
struct PluginManifestV1Draft: Codable, Sendable {
    let manifest: NocPluginManifest

    init(manifest: NocPluginManifest) {
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

    init(from decoder: any Decoder) throws {
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

    func encode(to encoder: any Encoder) throws {
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

// MARK: - Plugin metadata fields shared by all v1-draft plugin manifests

/// `NoctilucaPluginMetadata` 인터페이스에 정의된 공통 필드.
private struct PluginMetadataFieldsV1Draft: Codable, Sendable {
    let id: String
    let name: NocPluginLocalizableString
    let description: NocPluginLocalizableString
    let authors: [String]
    let license: SoftwareLicenseV1Draft
    let version: UInt32
    let displayVersion: String
}

// MARK: - AuthPluginManifestV1Draft

struct AuthPluginManifestV1Draft: AuthPluginManifest, Codable {
    let id: String
    let type: NoctilucaPluginType = .auth
    let name: NocPluginLocalizableString
    let pluginDescription: NocPluginLocalizableString
    let authors: [String]
    let license: SoftwareLicense
    let version: UInt32
    let displayVersion: String

    let supportedMethods: [String]

    private enum CodingKeys: String, CodingKey {
        case id, type
        case name, description
        case authors, license, version, displayVersion
        case supportedMethods
    }

    init(from decoder: any Decoder) throws {
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

    func encode(to encoder: any Encoder) throws {
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

struct KeyboardHackPluginManifestV1Draft: KeyboardHackPluginManifest, Codable {
    let id: String
    let type: NoctilucaPluginType = .keyboardHack
    let name: NocPluginLocalizableString
    let pluginDescription: NocPluginLocalizableString
    let authors: [String]
    let license: SoftwareLicense
    let version: UInt32
    let displayVersion: String

    let desiredKeyEvents: [String]

    private enum CodingKeys: String, CodingKey {
        case id, type
        case name, description
        case authors, license, version, displayVersion
        case desiredKeyEvents
    }

    init(from decoder: any Decoder) throws {
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

    func encode(to encoder: any Encoder) throws {
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

struct RPCHandlerPluginManifestV1Draft: RPCHandlerPluginManifest, Codable {
    let id: String
    let type: NoctilucaPluginType = .rpcHandler
    let name: NocPluginLocalizableString
    let pluginDescription: NocPluginLocalizableString
    let authors: [String]
    let license: SoftwareLicense
    let version: UInt32
    let displayVersion: String

    let supportedOperations: [String]

    private enum CodingKeys: String, CodingKey {
        case id, type
        case name, description
        case authors, license, version, displayVersion
        case supportedOperations
    }

    init(from decoder: any Decoder) throws {
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

    func encode(to encoder: any Encoder) throws {
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
