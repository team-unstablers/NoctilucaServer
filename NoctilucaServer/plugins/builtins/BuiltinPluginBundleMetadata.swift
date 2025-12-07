//
//  PluginBundleInfo.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/7/25.
//

import NoctilucaPluginKit

struct BuiltinPluginBundleExportMetadata: PluginBundleExportMetadata {
    let id: String
    let displayName: String
    let type: NoctilucaPluginType
    let description: String
}

struct BuiltinPluginBundleMetadata: PluginBundleMetadata {
    let id: String
    let displayName: String
    
    let version: UInt32
    let displayVersion: String
    
    let pluginKitVersion: NoctilucaPluginKitVersion
    let description: String
    
    let authors: [String]
    let license: SoftwareLicense
    
    let exports: [any PluginBundleExportMetadata]
}
