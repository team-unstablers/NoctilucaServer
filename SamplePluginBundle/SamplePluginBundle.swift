//
//  SamplePluginBundle.swift
//  SamplePluginBundle
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

import NoctilucaPluginKit

public final class SamplePluginBundle: NoctilucaPluginBundle {
    public static let id = "app.noctiluca.pluginkit.example.SamplePluginBundle"
    public static var pluginKitVersion: NoctilucaPluginKitVersion = .v1
    
    public static var name = String(localized: "plugin.name", defaultValue: "기본 키보드 핵 번들")
    public static var description = String(localized: "plugin.description", defaultValue: "사용성 개선을 위한 키보드 핵(Hack)을 클라이언트에게 제공합니다.")
    
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
    ]
}
