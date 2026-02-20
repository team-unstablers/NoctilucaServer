//
//  PluginBundleInfo.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/7/25.
//

import Foundation
import NoctilucaPluginKit

struct PluginBundleMetadataParsingError: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

struct PluginBundleExportPlistMetadata: PluginBundleExportMetadata {
    let id: String
    let displayName: String
    let type: NoctilucaPluginType
    let description: String

    init(id: String, displayName: String,
         type: NoctilucaPluginType,
         description: String)
    {
        self.id = id
        self.displayName = displayName
        self.type = type
        self.description = description
    }

    init(from infoPlist: [String: Any]) throws {
        var missingKeys: [String] = []

        let id          = infoPlist.value(pluginInfoKey: .id) as? String
        let displayName = infoPlist.value(pluginInfoKey: .displayName) as? String
        let typeRaw     = infoPlist.value(pluginInfoKey: .type) as? String
        let description = infoPlist.value(pluginInfoKey: .description) as? String

        if id == nil          { missingKeys.append(NoctilucaPluginInfoPlistKey.id.rawValue) }
        if displayName == nil { missingKeys.append(NoctilucaPluginInfoPlistKey.displayName.rawValue) }
        if typeRaw == nil     { missingKeys.append(NoctilucaPluginInfoPlistKey.type.rawValue) }
        if description == nil { missingKeys.append(NoctilucaPluginInfoPlistKey.description.rawValue) }

        if !missingKeys.isEmpty {
            throw PluginBundleMetadataParsingError(
                reason: "Missing export keys: \(missingKeys.joined(separator: ", "))"
            )
        }

        guard let type = NoctilucaPluginType(rawValue: typeRaw!) else {
            throw PluginBundleMetadataParsingError(
                reason: "Invalid \(NoctilucaPluginInfoPlistKey.type.rawValue) value '\(typeRaw!)'"
                    + " (expected one of: auth, feature, extension, keyboard_hack)"
            )
        }

        self.init(id: id!, displayName: displayName!, type: type, description: description!)
    }
}

/// PluginBundle.nocbundle/Contents/Info.plist
struct PluginBundlePlistMetadata: PluginBundleMetadata {
    let id: String
    let displayName: String
    
    let version: UInt32
    let displayVersion: String
    
    let pluginKitVersion: NoctilucaPluginKitVersion
    let description: String
    
    let authors: [String]
    let license: SoftwareLicense
    
    let exports: [any PluginBundleExportMetadata]
    
    
    init(id: String, displayName: String,
         version: UInt32, displayVersion: String,
         pluginKitVersion: NoctilucaPluginKitVersion, description: String,
         authors: [String], license: SoftwareLicense,
         exports: [any PluginBundleExportMetadata])
    {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.displayVersion = displayVersion
        self.pluginKitVersion = pluginKitVersion
        self.description = description
        self.authors = authors
        self.license = license
        self.exports = exports
    }
   
    init(from infoPlist: [String: Any]) throws {
        var missingKeys: [String] = []

        let id                  = infoPlist.value(pluginBundleInfoKey: .id) as? String
        let displayName         = infoPlist.value(pluginBundleInfoKey: .displayName) as? String
        let versionStr          = infoPlist.value(pluginBundleInfoKey: .version) as? String
        let displayVersion      = infoPlist.value(pluginBundleInfoKey: .displayVersion) as? String
        let pluginKitVersionRaw = infoPlist.value(pluginBundleInfoKey: .pluginKitVersion) as? UInt32
        let bundleDescription   = infoPlist.value(pluginBundleInfoKey: .bundleDescription) as? String
        let authors             = infoPlist.value(pluginBundleInfoKey: .bundleAuthors) as? [String]
        let licenseSPDX         = infoPlist.value(pluginBundleInfoKey: .bundleLicense) as? String
        let exportsInfo         = infoPlist.value(pluginBundleInfoKey: .bundleExports) as? [[String: Any]]

        if id == nil                  { missingKeys.append(NoctilucaPluginBundleInfoPlistKey.id.rawValue) }
        if displayName == nil         { missingKeys.append(NoctilucaPluginBundleInfoPlistKey.displayName.rawValue) }
        if versionStr == nil          { missingKeys.append(NoctilucaPluginBundleInfoPlistKey.version.rawValue) }
        if displayVersion == nil      { missingKeys.append(NoctilucaPluginBundleInfoPlistKey.displayVersion.rawValue) }
        if pluginKitVersionRaw == nil { missingKeys.append(NoctilucaPluginBundleInfoPlistKey.pluginKitVersion.rawValue) }
        if bundleDescription == nil   { missingKeys.append(NoctilucaPluginBundleInfoPlistKey.bundleDescription.rawValue) }
        if authors == nil             { missingKeys.append(NoctilucaPluginBundleInfoPlistKey.bundleAuthors.rawValue) }
        if licenseSPDX == nil         { missingKeys.append(NoctilucaPluginBundleInfoPlistKey.bundleLicense.rawValue) }
        if exportsInfo == nil         { missingKeys.append(NoctilucaPluginBundleInfoPlistKey.bundleExports.rawValue) }

        if !missingKeys.isEmpty {
            throw PluginBundleMetadataParsingError(
                reason: "Missing or invalid Info.plist keys: \(missingKeys.joined(separator: ", "))"
            )
        }

        guard let version = Int(versionStr!) else {
            throw PluginBundleMetadataParsingError(
                reason: "\(NoctilucaPluginBundleInfoPlistKey.version.rawValue) is not a valid integer: '\(versionStr!)'"
            )
        }

        // optional
        let licenseURL = infoPlist.value(pluginBundleInfoKey: .bundleLicenseURL) as? String

        var exports: [PluginBundleExportPlistMetadata] = []
        for (index, exportInfo) in exportsInfo!.enumerated() {
            do {
                let export = try PluginBundleExportPlistMetadata(from: exportInfo)
                exports.append(export)
            } catch {
                throw PluginBundleMetadataParsingError(
                    reason: "Failed to parse export at index \(index): \(error.localizedDescription)"
                )
            }
        }

        self.init(
            id: id!,
            displayName: displayName!,
            version: UInt32(version),
            displayVersion: displayVersion!,
            pluginKitVersion: NoctilucaPluginKitVersion(rawValue: pluginKitVersionRaw!),
            description: bundleDescription!,
            authors: authors!,
            license: SoftwareLicense.from(spdxIdentifier: licenseSPDX!, url: licenseURL),
            exports: exports
        )
    }
}

fileprivate extension Dictionary where Key == String, Value == Any {
    /// RawRepresentable<String> 키로 값을 가져옵니다.
    func value(pluginInfoKey: NoctilucaPluginInfoPlistKey) -> Value? {
        return self[pluginInfoKey.rawValue]
    }
    
    func value(pluginBundleInfoKey: NoctilucaPluginBundleInfoPlistKey) -> Value? {
        return self[pluginBundleInfoKey.rawValue]
    }
}
