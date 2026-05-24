//
//  XPCLoader.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 5/17/26.
//

import Foundation
import NoctilucaPluginKit
import NoctilucaPluginKitHostCore
import Shotoku

import XPC

import SiriusKit

/// `HostControlInterface` proxy 의 `bundle_*` forwarding method 를 호출하여
/// host process 너머의 plugin bundle 에 대한 bundle-level action 액세스를
/// 제공.
private final class XPCBundleAccessor: PluginBundleAccessor {
    private let proxy: any HostControlInterface

    init(_ proxy: any HostControlInterface) {
        self.proxy = proxy
    }

    func supportedActions() async throws -> [NoctilucaPluginBundleAction] {
        try await proxy.bundle_supportedActions()
    }

    func dispatchAction(_ action: NoctilucaPluginBundleAction) async throws {
        try await proxy.bundle_dispatchAction(action)
    }
}

/// `HostControlInterface` proxy 를 `KeyboardHackPluginV1RPC` surface 로 노출하는
/// thin bridge.
///
/// 한 host process 가 (multi-instance 라서) 한 bundle 을 load 하지만, 한 bundle
/// 안에서 같은 type 의 plugin 이 여러 개 export 될 수 있으므로, bridge 는
/// pluginId 를 보관하여 forwarding 호출의 첫 인자로 전달한다.
private final class HostControlKeyboardHackBridge: KeyboardHackPluginV1RPC {
    private let proxy: any HostControlInterface
    private let pluginId: String

    init(_ proxy: any HostControlInterface, pluginId: String) {
        self.proxy = proxy
        self.pluginId = pluginId
    }

    func id() async throws -> String {
        try await proxy.keyboardHack_id(pluginId: pluginId)
    }

    func desiredKeyEvents() async throws -> [NoctilucaPluginKit.LinuxKeycode] {
        try await proxy.keyboardHack_desiredKeyEvents(pluginId: pluginId)
    }

    func onKeyDown(_ keyCode: NoctilucaPluginKit.LinuxKeycode) async throws -> KeyboardHackResult {
        try await proxy.keyboardHack_onKeyDown(pluginId: pluginId, keyCode)
    }

    func onKeyUp(_ keyCode: NoctilucaPluginKit.LinuxKeycode) async throws -> KeyboardHackResult {
        try await proxy.keyboardHack_onKeyUp(pluginId: pluginId, keyCode)
    }
}

/// `HostControlInterface` proxy 를 `RPCHandlerPluginV1RPC` surface 로 노출하는
/// thin bridge. `HostControlKeyboardHackBridge` 와 같은 패턴으로 pluginId 를
/// 보관하여 forwarding 호출의 첫 인자로 전달한다.
private final class HostControlRPCHandlerBridge: RPCHandlerPluginV1RPC {
    private let proxy: any HostControlInterface
    private let pluginId: String

    init(_ proxy: any HostControlInterface, pluginId: String) {
        self.proxy = proxy
        self.pluginId = pluginId
    }

    func id() async throws -> String {
        try await proxy.rpcHandler_id(pluginId: pluginId)
    }

    func supportedOperations() async throws -> [String] {
        try await proxy.rpcHandler_supportedOperations(pluginId: pluginId)
    }

    func onRPCRequest(operation: String, args: [String]) async throws -> RPCResult {
        try await proxy.rpcHandler_onRPCRequest(pluginId: pluginId, operation: operation, args: args)
    }
}

/// `isolate` 매니페스트로 선언된 번들을 `NoctilucaPluginKitHost.xpc` 의 별도
/// process instance 에서 dlopen 하도록 위임한다.
///
/// 한 bundle = 한 host process instance (launchd `_MultipleInstances=YES`).
/// loadBundle 호출 시 server 가 새 `RPCClient<HostControlInterface>` 를
/// 생성하여 connect → loadBundle → 결과의 forwarding method 를
/// `KeyboardHackPluginV1RPC` bridge 로 wrap 하여 반환.
actor XPCLoader: PluginLoader {

    private let logger = NoctilucaLogger(category: "XPCLoader")
    private let hostServiceName = "app.noctiluca.server.NoctilucaPluginKitHost"

    /// bundleId → 활성 client (disconnect / unload 용)
    private var clients: [String: RPCClient<HostControlInterface>] = [:]

    init() {}

    func load(
        url: URL,
        manifest: any PluginBundleManifest
    ) async throws -> LoadedPluginExports {
        // docs/xpc-safety.md §3.3 — client-side OS-level gate.
        // libxpc 가 connection 시점에 host XPC service 의 DR 매칭을 평가한다.
        // 동일 service name 으로 다른 launchd 등록이 끼어든 경우 (사용자
        // LaunchAgent 우선순위 / 환경 변수 조작 등) 를 차단한다.
        let endpointOptions = RPCXPCEndpointOptions(
            peerCodeSigningRequirement: XPCPeerIdentity.hostPeerRequirement
        )
        let client = RPCClient<HostControlInterface>(
            endpoint: .xpc(hostServiceName, options: endpointOptions)
        )

        do {
            try await client.connect()
        } catch {
            logger.error("XPCLoader: failed to connect to host service for \(manifest.id): \(error)")
            throw PluginBundleRegistryError.initializationFailed(error: error)
        }

        let proxy: any HostControlInterface
        do {
            proxy = try await client.proxy(HostControlInterface.Proxy.self)
        } catch {
            logger.error("XPCLoader: failed to obtain proxy for \(manifest.id): \(error)")
            await client.disconnect()
            throw PluginBundleRegistryError.initializationFailed(error: error)
        }

        // health check (ping 응답에는 host 의 pid 가 포함되어 있어 multi-instance
        // 검증 시 server log 에서 host process 가 connection 별로 분리되는지
        // 확인할 수 있다.)
        do {
            let pongMessage = try await proxy.ping()
            logger.info("XPCLoader: host ping ok for \(manifest.id) — \(pongMessage)")
        } catch {
            logger.error("XPCLoader: ping failed for \(manifest.id): \(error)")
            await client.disconnect()
            throw PluginBundleRegistryError.initializationFailed(error: error)
        }

        let loadedInfo: LoadedBundleInfo
        do {
            loadedInfo = try await proxy.loadBundle(bundlePath: url.path)
        } catch {
            logger.error("XPCLoader: host loadBundle failed for \(manifest.id): \(error)")
            await client.disconnect()
            throw PluginBundleRegistryError.initializationFailed(error: error)
        }

        var proxies: [LoadedPluginProxy] = []
        for entry in loadedInfo.exports {
            switch entry.type {
            case .keyboardHack:
                let bridge = HostControlKeyboardHackBridge(proxy, pluginId: entry.pluginId)
                proxies.append(.keyboardHack(bridge))
            case .rpcHandler:
                let bridge = HostControlRPCHandlerBridge(proxy, pluginId: entry.pluginId)
                proxies.append(.rpcHandler(bridge))
            case .auth, .extension, .feature:
                // 본 PR 범위 밖.
                logger.warning("XPCLoader: unsupported plugin type \(entry.type.rawValue) in bundle \(manifest.id), skipping")
            @unknown default:
                logger.warning("XPCLoader: unknown plugin type for bundle \(manifest.id), skipping")
            }
        }

        let accessor = XPCBundleAccessor(proxy)

        clients[manifest.id] = client
        logger.info("XPCLoader: loaded bundle \(manifest.id) with \(proxies.count) proxy(s) via XPC")

        return LoadedPluginExports(
            bundleId: manifest.id,
            bundleClass: nil,
            manifest: manifest,
            proxies: proxies,
            accessor: accessor
        )
    }

    func unload(bundleId: String) async {
        guard let client = clients.removeValue(forKey: bundleId) else {
            return
        }
        do {
            let proxy = try await client.proxy(HostControlInterface.Proxy.self)
            try await proxy.unloadBundle()
        } catch {
            logger.warning("XPCLoader: unloadBundle remote call failed for \(bundleId): \(error)")
        }
        await client.disconnect()
        logger.info("XPCLoader: unloaded bundle \(bundleId)")
    }
}
