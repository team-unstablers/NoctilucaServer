//
//  HostControlInterface.swift
//  NoctilucaPluginKitHostCore
//
//  Created by Gyuhwan Park on 5/17/26.
//

import Foundation
import NoctilucaPluginKit
import Shotoku

/// `loadBundle` 응답. bundle 안에서 발견된 plugin export 들의 metadata.
///
/// 본 PR 범위에서는 endpoint Data (anonymous xpc_endpoint serialization) 를
/// 함께 운반하지 않는다 — Shotoku v0.1 이 cross-process anonymous endpoint
/// pattern 을 직접 지원하지 않기 때문. 대신 plugin type 별 forwarding method
/// 를 `HostControlInterface` 가 직접 expose 한다 (`keyboardHack_*` 등).
/// dual-interface (Shotoku v0.3) 도착 시 이 디자인은 정리될 예정.
public struct LoadedBundleInfo: Codable, Sendable {
    public let bundleId: String
    public let exports: [LoadedPluginInfo]

    public init(bundleId: String, exports: [LoadedPluginInfo]) {
        self.bundleId = bundleId
        self.exports = exports
    }
}

public struct LoadedPluginInfo: Codable, Sendable {
    public let pluginId: String
    public let type: NoctilucaPluginType

    public init(pluginId: String, type: NoctilucaPluginType) {
        self.pluginId = pluginId
        self.type = type
    }
}

public enum HostControlError: Error, Codable, Sendable {
    case bundleNotFound(path: String)
    case bundleLoadFailed(reason: String)
    case principalClassMismatch
    case initializeFailed(reason: String)
    case noExports
    case alreadyLoaded(bundleId: String)
    case notLoaded
    /// plugin 이 아직 load 되지 않았거나 해당 type 의 plugin 이 없는 경우.
    case pluginUnavailable(type: NoctilucaPluginType)
}

/// Host process bootstrap channel.
///
/// `loadBundle` 호출 전: `ping` / `loadBundle` 만 의미가 있음. `keyboardHack_*`
/// 등의 forwarding method 는 `pluginUnavailable` 을 throw.
///
/// `loadBundle` 호출 후: `keyboardHack_*` 등이 host 의 wrapped plugin 으로
/// 위임됨.
@RPCInterface
public protocol HostControlInterface: Sendable {

    // MARK: - Lifecycle

    @RPCProcedure
    func ping() async throws -> String

    @RPCProcedure
    func loadBundle(bundlePath: String) async throws -> LoadedBundleInfo

    @RPCProcedure
    func unloadBundle() async throws

    // MARK: - KeyboardHack forwarding
    //
    // `loadBundle` 후 활성화. plugin type 이 keyboardHack 이 아니면
    // `HostControlError.pluginUnavailable(type: .keyboardHack)` throw.

    @RPCProcedure
    func keyboardHack_id() async throws -> String

    @RPCProcedure
    func keyboardHack_desiredKeyEvents() async throws -> [LinuxKeycode]

    @RPCProcedure
    func keyboardHack_onKeyDown(_ keyCode: LinuxKeycode) async throws -> KeyboardHackResult

    @RPCProcedure
    func keyboardHack_onKeyUp(_ keyCode: LinuxKeycode) async throws -> KeyboardHackResult
}
