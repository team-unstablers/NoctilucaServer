//
//  PluginBundleManifestV1Draft.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 5/16/26.
//

import Foundation
@preconcurrency import NoctilucaPluginKit

/// v1-draft (`pluginKitVersion: 20260516`) 의 JSON 매니페스트 구현체.
struct PluginBundleManifestV1Draft: PluginBundleManifest, Codable {
    /// JSON Schema 의 `pluginKitVersion` 식별자.
    static let pluginKitVersionTag: String = "20260516"

    let schemaURL: String?

    let id: String
    let name: NocPluginLocalizableString
    let bundleDescription: NocPluginLocalizableString

    let authors: [String]
    let license: SoftwareLicense

    let url: String?

    let pluginKitVersion: NoctilucaPluginKitVersion
    let isolationPolicy: PluginIsolationPolicy
    let exports: [NocPluginManifest]

    private enum CodingKeys: String, CodingKey {
        case schemaURL = "$schema"
        case id
        case name
        case description
        case authors
        case license
        case url
        case pluginKitVersion
        case isolationPolicy
        case exports
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.schemaURL = try container.decodeIfPresent(String.self, forKey: .schemaURL)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(NocPluginLocalizableString.self, forKey: .name)
        self.bundleDescription = try container.decode(NocPluginLocalizableString.self, forKey: .description)
        self.authors = try container.decode([String].self, forKey: .authors)
        self.license = try container.decode(SoftwareLicenseV1Draft.self, forKey: .license).resolved
        self.url = try container.decodeIfPresent(String.self, forKey: .url)

        // pluginKitVersion: TS string literal '20260516' → NoctilucaPluginKitVersion.v1
        let rawPluginKitVersion = try container.decode(String.self, forKey: .pluginKitVersion)
        guard rawPluginKitVersion == Self.pluginKitVersionTag else {
            throw DecodingError.dataCorruptedError(
                forKey: .pluginKitVersion,
                in: container,
                debugDescription: "Unsupported pluginKitVersion '\(rawPluginKitVersion)'"
                    + " (expected '\(Self.pluginKitVersionTag)' for v1-draft)"
            )
        }
        self.pluginKitVersion = .v1

        // isolationPolicy: 'isolate' | 'no-isolate'
        let rawPolicy = try container.decode(String.self, forKey: .isolationPolicy)
        switch rawPolicy {
        case "isolate":
            self.isolationPolicy = .isolate
        case "no-isolate":
            self.isolationPolicy = .noIsolate
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .isolationPolicy,
                in: container,
                debugDescription: "Unknown isolationPolicy '\(rawPolicy)'"
                    + " (expected 'isolate' or 'no-isolate')"
            )
        }

        // exports: discriminator (`type` field) 기반으로 v1-draft plugin manifest 디코딩
        let wrappers = try container.decode([PluginManifestV1Draft].self, forKey: .exports)
        self.exports = wrappers.map { $0.manifest }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encodeIfPresent(schemaURL, forKey: .schemaURL)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(bundleDescription, forKey: .description)
        try container.encode(authors, forKey: .authors)
        try container.encode(SoftwareLicenseV1Draft(license), forKey: .license)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(Self.pluginKitVersionTag, forKey: .pluginKitVersion)

        switch isolationPolicy {
        case .isolate:
            try container.encode("isolate", forKey: .isolationPolicy)
        case .noIsolate:
            try container.encode("no-isolate", forKey: .isolationPolicy)
        }

        let wrappers = exports.map { PluginManifestV1Draft(manifest: $0) }
        try container.encode(wrappers, forKey: .exports)
    }
}
