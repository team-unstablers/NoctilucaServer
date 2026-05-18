//
//  HostControlInterfaceImpl.swift
//  NoctilucaPluginKitHost
//
//  Created by Gyuhwan Park on 5/17/26.
//

import Foundation
import NoctilucaPluginKit
import NoctilucaPluginKitHostCore
import Shotoku

/// Host process 의 `HostControlInterface` 구현.
///
/// 한 host process instance 는 한 번에 하나의 plugin bundle 만 load 한다
/// (launchd 가 `_MultipleInstances=YES` 로 instance 를 띄우므로, server 가
/// bundle 마다 별도 host instance 와 통신).
@RPCService
actor HostControlInterfaceImpl: HostControlInterface {

    private var loadedBundleClass: NoctilucaPluginBundle.Type?
    private var loadedBundleId: String?
    private var keyboardHackAdapter: KeyboardHackPluginV1Adapter?

    init() {}

    // MARK: - Lifecycle

    func ping() async throws -> String {
        // pid 를 포함해서 multi-instance 검증 시 server log 에 host process
        // identifier 가 노출되도록 한다.
        let pid = ProcessInfo.processInfo.processIdentifier
        return "pong (pid=\(pid))"
    }

    func loadBundle(bundlePath: String) async throws -> LoadedBundleInfo {
        if let existing = loadedBundleId {
            throw HostControlError.alreadyLoaded(bundleId: existing)
        }

        let url = URL(fileURLWithPath: bundlePath)
        guard let bundle = Bundle(url: url) else {
            throw HostControlError.bundleNotFound(path: bundlePath)
        }

        guard bundle.load() else {
            throw HostControlError.bundleLoadFailed(reason: "Bundle.load() returned false")
        }

        guard let bundleClass = bundle.principalClass as? NoctilucaPluginBundle.Type else {
            throw HostControlError.principalClassMismatch
        }

        do {
            try await bundleClass.initialize()
        } catch {
            throw HostControlError.initializeFailed(reason: String(describing: error))
        }

        let exports = bundleClass.exports
        guard !exports.isEmpty else {
            throw HostControlError.noExports
        }

        var pluginInfos: [LoadedPluginInfo] = []
        for export in exports {
            switch export {
            case .keyboardHack(let plugin):
                self.keyboardHackAdapter = KeyboardHackPluginV1Adapter(wrapping: plugin)
                pluginInfos.append(LoadedPluginInfo(
                    pluginId: type(of: plugin).id,
                    type: .keyboardHack
                ))
            case .auth(let plugin):
                // 본 PR 범위 밖. metadata 만 보고.
                let pluginId = type(of: plugin).id
                pluginInfos.append(LoadedPluginInfo(pluginId: pluginId, type: .auth))
            case .extension(let plugin):
                pluginInfos.append(LoadedPluginInfo(
                    pluginId: type(of: plugin).id,
                    type: .extension
                ))
            case .rpcHandler(let plugin):
                pluginInfos.append(LoadedPluginInfo(
                    pluginId: type(of: plugin).id,
                    type: .rpcHandler
                ))
            @unknown default:
                continue
            }
        }

        let bundleId = (bundle.bundleIdentifier ?? bundlePath)
        self.loadedBundleClass = bundleClass
        self.loadedBundleId = bundleId

        return LoadedBundleInfo(bundleId: bundleId, exports: pluginInfos)
    }

    func unloadBundle() async throws {
        guard let bundleClass = loadedBundleClass else {
            throw HostControlError.notLoaded
        }

        do {
            try bundleClass.deinitialize()
        } catch {
            // deinitialize 실패해도 state 는 cleanup
        }

        self.loadedBundleClass = nil
        self.loadedBundleId = nil
        self.keyboardHackAdapter = nil
    }

    // MARK: - Bundle action forwarding

    func bundle_supportedActions() async throws -> [NoctilucaPluginBundleAction] {
        guard let bundleClass = loadedBundleClass else {
            throw HostControlError.notLoaded
        }
        return bundleClass.supportedActions
    }

    func bundle_dispatchAction(_ action: NoctilucaPluginBundleAction) async throws {
        guard let bundleClass = loadedBundleClass else {
            throw HostControlError.notLoaded
        }
        try await bundleClass.dispatchAction(action: action)
    }

    // MARK: - KeyboardHack forwarding

    func keyboardHack_id() async throws -> String {
        guard let adapter = keyboardHackAdapter else {
            throw HostControlError.pluginUnavailable(type: .keyboardHack)
        }
        return try await adapter.id()
    }

    func keyboardHack_desiredKeyEvents() async throws -> [LinuxKeycode] {
        guard let adapter = keyboardHackAdapter else {
            throw HostControlError.pluginUnavailable(type: .keyboardHack)
        }
        return try await adapter.desiredKeyEvents()
    }

    func keyboardHack_onKeyDown(_ keyCode: LinuxKeycode) async throws -> KeyboardHackResult {
        guard let adapter = keyboardHackAdapter else {
            throw HostControlError.pluginUnavailable(type: .keyboardHack)
        }
        return try await adapter.onKeyDown(keyCode)
    }

    func keyboardHack_onKeyUp(_ keyCode: LinuxKeycode) async throws -> KeyboardHackResult {
        guard let adapter = keyboardHackAdapter else {
            throw HostControlError.pluginUnavailable(type: .keyboardHack)
        }
        return try await adapter.onKeyUp(keyCode)
    }
}
