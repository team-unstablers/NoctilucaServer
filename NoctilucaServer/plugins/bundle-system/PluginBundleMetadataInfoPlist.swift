//
//  PluginBundleInfo.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/7/25.
//

import NoctilucaPluginKit

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
    
    init?(from infoPlist: [String: Any]) {
        guard let id          = infoPlist.value(pluginInfoKey: .id) as? String,
              let displayName = infoPlist.value(pluginInfoKey: .displayName) as? String,
              let typeRaw     = infoPlist.value(pluginInfoKey: .type) as? String,
              let description = infoPlist.value(pluginInfoKey: .description) as? String
        else {
            return nil
        }
        
        guard let type = NoctilucaPluginType(rawValue: typeRaw) else {
            return nil
        }
        
        self.init(
            id: id,
            displayName: displayName,
            type: type,
            description: description
        )
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
   
    init?(from infoPlist: [String: Any]) {
        guard let id          = infoPlist.value(pluginBundleInfoKey: .id) as? String,
              let displayName = infoPlist.value(pluginBundleInfoKey: .displayName) as? String,
              let versionStr  = infoPlist.value(pluginBundleInfoKey: .version) as? String,
              let version     = Int(versionStr),
              let displayVersion = infoPlist.value(pluginBundleInfoKey: .displayVersion) as? String,
              let pluginKitVersionRaw = infoPlist.value(pluginBundleInfoKey: .pluginKitVersion) as? UInt32,
              let bundleDescription = infoPlist.value(pluginBundleInfoKey: .bundleDescription) as? String,
              let authors     = infoPlist.value(pluginBundleInfoKey: .bundleAuthors) as? [String],
              let licenseSPDX = infoPlist.value(pluginBundleInfoKey: .bundleLicense) as? String,
              let exportsInfo = infoPlist.value(pluginBundleInfoKey: .bundleExports) as? [[String: Any]]
        else {
            return nil
        }
        
        
        // optional
        let licenseURL = infoPlist.value(pluginBundleInfoKey: .bundleLicenseURL) as? String

        let exports = exportsInfo.map { PluginBundleExportPlistMetadata(from: $0) }
        
        if exports.contains(where: { $0 == nil }) {
            // strict parsing >_<;
            return nil
        }
        
        self.init(
            id: id,
            displayName: displayName,
            version: UInt32(version),
            displayVersion: displayVersion,
            pluginKitVersion: NoctilucaPluginKitVersion(rawValue: pluginKitVersionRaw),
            description: bundleDescription,
            authors: authors,
            license: SoftwareLicense.from(spdxIdentifier: licenseSPDX, url: licenseURL),
            exports: exports.compactMap { $0 }
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
