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
/// 본 응답에는 endpoint Data (anonymous xpc_endpoint serialization) 를 함께
/// 운반하지 않는다 — **XPC 자체의 설계 제약상 `xpc_endpoint_t` 는 wire
/// serialize 가 불가능 (= 다른 프로세스로 운반 불가) 하기 때문**. Shotoku
/// 라이브러리 한계가 아니라 XPC 프리미티브의 한계.
///
/// 대신 plugin type 별 forwarding method 를 `HostControlInterface` 가 직접
/// expose 한다 (`keyboardHack_*` / `rpcHandler_*` 등). 한 bundle 이 같은
/// type 의 plugin 을 여러 개 export 할 수 있으므로, forwarding method 들은
/// 첫 번째 인자로 `pluginId` 를 받아 host 가 plugin 별 adapter 로 분기할 수
/// 있게 한다. dual-interface (Shotoku v0.3) 도착 시 이 디자인은 재검토 예정.
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
    /// 주어진 pluginId 의 plugin 을 해당 type adapter dict 에서 찾을 수 없는 경우.
    case pluginNotFound(type: NoctilucaPluginType, pluginId: String)
}

/// Host process bootstrap channel.
///
/// `loadBundle` 호출 전: `ping` / `loadBundle` 만 의미가 있음. `keyboardHack_*`
/// / `rpcHandler_*` 등의 forwarding method 는 `pluginUnavailable` 을 throw.
///
/// `loadBundle` 호출 후: forwarding method 들이 첫 번째 인자 `pluginId` 로
/// host 의 plugin-type 별 adapter dict 에서 lookup 하여 wrapped plugin 으로
/// 위임됨. 해당 type 의 plugin 이 하나도 없으면 `pluginUnavailable`, 해당
/// pluginId 매칭이 없으면 `pluginNotFound` 를 throw.
@RPCInterface
public protocol HostControlInterface: Sendable {

    // MARK: - Lifecycle

    @RPCProcedure
    func ping() async throws -> String

    @RPCProcedure
    func loadBundle(bundlePath: String) async throws -> LoadedBundleInfo

    @RPCProcedure
    func unloadBundle() async throws

    // MARK: - Bundle action forwarding
    //
    // `loadBundle` 후 활성화. plugin type 과 무관하게 bundle 전체에 적용되는
    // action (예: `showSettingsUI`). bundle 이 load 되지 않은 상태에서는
    // `HostControlError.notLoaded` throw.

    @RPCProcedure
    func bundle_supportedActions() async throws -> [NoctilucaPluginBundleAction]

    @RPCProcedure
    func bundle_dispatchAction(_ action: NoctilucaPluginBundleAction) async throws

    // MARK: - KeyboardHack forwarding
    //
    // `loadBundle` 후 활성화. 첫 번째 인자 `pluginId` 로 host 의
    // keyboardHack adapter dict 에서 lookup 한다. plugin type 자체가 없으면
    // `HostControlError.pluginUnavailable(type: .keyboardHack)`, pluginId
    // 매칭이 없으면 `HostControlError.pluginNotFound(...)` throw.

    @RPCProcedure
    func keyboardHack_id(pluginId: String) async throws -> String

    @RPCProcedure
    func keyboardHack_desiredKeyEvents(pluginId: String) async throws -> [LinuxKeycode]

    @RPCProcedure
    func keyboardHack_onKeyDown(pluginId: String, _ keyCode: LinuxKeycode) async throws -> KeyboardHackResult

    @RPCProcedure
    func keyboardHack_onKeyUp(pluginId: String, _ keyCode: LinuxKeycode) async throws -> KeyboardHackResult

    // MARK: - RPCHandler forwarding
    //
    // `loadBundle` 후 활성화. 첫 번째 인자 `pluginId` 로 host 의 rpcHandler
    // adapter dict 에서 lookup 한다. plugin type 자체가 없으면
    // `HostControlError.pluginUnavailable(type: .rpcHandler)`, pluginId 매칭이
    // 없으면 `HostControlError.pluginNotFound(...)` throw.

    @RPCProcedure
    func rpcHandler_id(pluginId: String) async throws -> String

    @RPCProcedure
    func rpcHandler_supportedOperations(pluginId: String) async throws -> [String]

    @RPCProcedure
    func rpcHandler_onRPCRequest(pluginId: String, operation: String, args: [String]) async throws -> RPCResult
}
