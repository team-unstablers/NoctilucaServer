//
//  PluginBundleInfo.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/7/25.
//

import NoctilucaPluginKit

protocol PluginBundleExportMetadata: Identifiable {
    var id: String { get }
    var displayName: String { get }
    var type: NoctilucaPluginType { get }
    var description: String { get }
}

protocol PluginBundleMetadata: Identifiable {
    var id: String { get }
    var displayName: String { get }
    
    var version: UInt32 { get }
    var displayVersion: String { get }
    
    var pluginKitVersion: NoctilucaPluginKitVersion { get }
    var description: String { get }
    
    var authors: [String] { get }
    var license: SoftwareLicense { get }
    
    var exports: [any PluginBundleExportMetadata] { get }
}
