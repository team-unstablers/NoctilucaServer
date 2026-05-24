//
//  PluginManifest.swift
//  NoctilucaPluginKitHostCore
//
//  Created by Gyuhwan Park on 5/16/26.
//

import Foundation
import NoctilucaPluginKit

/// 번들 내 개별 플러그인 export 의 공통 contract.
public protocol PluginManifest: Identifiable, Sendable {
    var id: String { get }
    var type: NoctilucaPluginType { get }

    var name: NocPluginLocalizableString { get }
    var pluginDescription: NocPluginLocalizableString { get }

    var authors: [String] { get }
    var license: SoftwareLicense { get }

    var version: UInt32 { get }
    var displayVersion: String { get }
}

/// `auth_v1` 플러그인 매니페스트.
public protocol AuthPluginManifest: PluginManifest {
    var supportedMethods: [String] { get }
}

/// `keyboard_hack_v1` 플러그인 매니페스트.
///
/// `desiredKeyEvents` 는 Linux `KEY_*` 식별자 문자열입니다.
/// `LinuxKeycode` 로의 변환은 사용처에서 별도 매핑하여 수행합니다.
public protocol KeyboardHackPluginManifest: PluginManifest {
    var desiredKeyEvents: [String] { get }
}

/// `rpc_handler_v1` 플러그인 매니페스트.
public protocol RPCHandlerPluginManifest: PluginManifest {
    var supportedOperations: [String] { get }
}

/// `NoctilucaPlugin` union (auth_v1 | keyboard_hack_v1 | rpc_handler_v1) 의 Swift 표현.
public enum NocPluginManifest: Sendable {
    case auth(any AuthPluginManifest)
    case keyboardHack(any KeyboardHackPluginManifest)
    case rpcHandler(any RPCHandlerPluginManifest)

    public var manifest: any PluginManifest {
        switch self {
        case .auth(let m): return m
        case .keyboardHack(let m): return m
        case .rpcHandler(let m): return m
        }
    }

    public var type: NoctilucaPluginType {
        switch self {
        case .auth: return .auth
        case .keyboardHack: return .keyboardHack
        case .rpcHandler: return .rpcHandler
        }
    }

    public var id: String { manifest.id }
}
