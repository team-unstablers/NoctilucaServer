//
//  SamplePluginBundle.swift
//  SamplePluginBundle
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

import NoctilucaPluginKit

public final class SamplePluginBundle: NoctilucaPluginBundle {
    public static let id = "pl.unstabler.noctiluca.plugin.example.SamplePluginBundle"
    public static var pluginKitVersion: NoctilucaPluginKitVersion = .v1
    
    public static var name = NSLocalizedString("plugin.name", comment: "SamplePluginBundle")
    public static var description = NSLocalizedString("plugin.description", comment: "A sample plugin bundle for testing purposes.")
    
    public static var authors: [String] = [
        "Gyuhwan Park <unstabler@unstabler.pl>"
    ]
    
    public static var license: NoctilucaPluginKit.SoftwareLicense = .cc0
    public static var version: UInt32 = 1
    public static var displayVersion: String = "1.0.0"
    
    public static func initialize() async throws {
        print("Hello, World!")
    }
    
    public static func deinitialize() throws {
        print("Goodbye, World!")
    }
    
    public static var exports: [NoctilucaPluginKit.NoctilucaPluginExport] = [
        .auth(NullAuthPlugin())
    ]
}
