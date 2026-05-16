//
//  BuiltinPluginBundleManifest.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/7/25.
//

import Foundation
@preconcurrency import NoctilucaPluginKit

// MARK: - Bundle manifest

/// 앱 내장 플러그인 번들의 in-memory `PluginBundleManifest` 구현체.
///
/// JSON 매니페스트로부터 디코딩되는 외부 번들과 달리, 내장 번들은 코드에서 직접
/// 구성한 manifest 를 사용합니다. `NocPluginLocalizableString` 는 단일 default
/// string 으로 채워집니다 (로컬라이즈는 `NSLocalizedString` 호출 시점에 이미 끝남).
struct BuiltinPluginBundleManifest: PluginBundleManifest {
    let id: String
    let name: NocPluginLocalizableString
    let bundleDescription: NocPluginLocalizableString

    let authors: [String]
    let license: SoftwareLicense

    let url: String?

    let pluginKitVersion: NoctilucaPluginKitVersion
    let isolationPolicy: PluginIsolationPolicy
    let exports: [NocPluginManifest]

    init(
        id: String,
        name: String,
        bundleDescription: String,
        authors: [String],
        license: SoftwareLicense,
        url: String? = nil,
        pluginKitVersion: NoctilucaPluginKitVersion,
        isolationPolicy: PluginIsolationPolicy = .noIsolate,
        exports: [NocPluginManifest]
    ) {
        self.id = id
        self.name = NocPluginLocalizableString(name)
        self.bundleDescription = NocPluginLocalizableString(bundleDescription)
        self.authors = authors
        self.license = license
        self.url = url
        self.pluginKitVersion = pluginKitVersion
        self.isolationPolicy = isolationPolicy
        self.exports = exports
    }
}

// MARK: - Plugin manifests (auth / keyboard hack / rpc handler)

/// 내장 auth 플러그인의 `AuthPluginManifest` 구현체.
struct BuiltinAuthPluginManifest: AuthPluginManifest {
    let id: String
    let type: NoctilucaPluginType = .auth
    let name: NocPluginLocalizableString
    let pluginDescription: NocPluginLocalizableString
    let authors: [String]
    let license: SoftwareLicense
    let version: UInt32
    let displayVersion: String

    let supportedMethods: [String]

    init(
        id: String,
        name: String,
        pluginDescription: String,
        authors: [String],
        license: SoftwareLicense,
        version: UInt32,
        displayVersion: String,
        supportedMethods: [String]
    ) {
        self.id = id
        self.name = NocPluginLocalizableString(name)
        self.pluginDescription = NocPluginLocalizableString(pluginDescription)
        self.authors = authors
        self.license = license
        self.version = version
        self.displayVersion = displayVersion
        self.supportedMethods = supportedMethods
    }
}

/// 내장 keyboard-hack 플러그인의 `KeyboardHackPluginManifest` 구현체.
struct BuiltinKeyboardHackPluginManifest: KeyboardHackPluginManifest {
    let id: String
    let type: NoctilucaPluginType = .keyboardHack
    let name: NocPluginLocalizableString
    let pluginDescription: NocPluginLocalizableString
    let authors: [String]
    let license: SoftwareLicense
    let version: UInt32
    let displayVersion: String

    let desiredKeyEvents: [String]

    init(
        id: String,
        name: String,
        pluginDescription: String,
        authors: [String],
        license: SoftwareLicense,
        version: UInt32,
        displayVersion: String,
        desiredKeyEvents: [String]
    ) {
        self.id = id
        self.name = NocPluginLocalizableString(name)
        self.pluginDescription = NocPluginLocalizableString(pluginDescription)
        self.authors = authors
        self.license = license
        self.version = version
        self.displayVersion = displayVersion
        self.desiredKeyEvents = desiredKeyEvents
    }
}

/// 내장 rpc-handler 플러그인의 `RPCHandlerPluginManifest` 구현체.
struct BuiltinRPCHandlerPluginManifest: RPCHandlerPluginManifest {
    let id: String
    let type: NoctilucaPluginType = .rpcHandler
    let name: NocPluginLocalizableString
    let pluginDescription: NocPluginLocalizableString
    let authors: [String]
    let license: SoftwareLicense
    let version: UInt32
    let displayVersion: String

    let supportedOperations: [String]

    init(
        id: String,
        name: String,
        pluginDescription: String,
        authors: [String],
        license: SoftwareLicense,
        version: UInt32,
        displayVersion: String,
        supportedOperations: [String]
    ) {
        self.id = id
        self.name = NocPluginLocalizableString(name)
        self.pluginDescription = NocPluginLocalizableString(pluginDescription)
        self.authors = authors
        self.license = license
        self.version = version
        self.displayVersion = displayVersion
        self.supportedOperations = supportedOperations
    }
}
