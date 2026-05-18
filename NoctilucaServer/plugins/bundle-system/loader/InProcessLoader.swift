//
//  InProcessLoader.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 5/17/26.
//

import Foundation
import NoctilucaPluginKit
import NoctilucaPluginKitHostCore

import SiriusKit

/// `no-isolate` 매니페스트로 선언된 번들을 server 본체 프로세스 내에서
/// `Bundle.load()` 로 dlopen 한다.
///
/// codesign / isolation policy 검증은 `PluginBundleRegistry` 가 loader 호출
/// 이전에 수행. 본 loader 는 검증 통과를 전제로 한다.
actor InProcessLoader: PluginLoader {

    private let logger = NoctilucaLogger(category: "InProcessLoader")

    /// bundleId → loaded principal class (deinitialize 호출용)
    private var loadedBundles: [String: NoctilucaPluginBundle.Type] = [:]

    init() {}

    func load(
        url: URL,
        manifest: any PluginBundleManifest
    ) async throws -> LoadedPluginExports {
        guard let bundle = Bundle(url: url) else {
            throw PluginBundleRegistryError.invalidBundle
        }

        guard bundle.load() else {
            logger.error("InProcessLoader: Bundle.load() returned false for \(url.path)")
            throw PluginBundleRegistryError.rejectedBySystem
        }

        guard let bundleClass = bundle.principalClass as? NoctilucaPluginBundle.Type else {
            logger.error("InProcessLoader: principal class is not a NoctilucaPluginBundle for \(url.path)")
            throw PluginBundleRegistryError.invalidBundle
        }

        do {
            try await bundleClass.initialize()
        } catch {
            logger.error("InProcessLoader: bundle initialization failed for \(manifest.id): \(error)")
            try? bundleClass.deinitialize()
            throw PluginBundleRegistryError.initializationFailed(error: error)
        }

        var proxies: [LoadedPluginProxy] = []
        for export in bundleClass.exports {
            switch export {
            case .keyboardHack(let plugin):
                let adapter = KeyboardHackPluginV1Adapter(wrapping: plugin)
                proxies.append(.keyboardHack(adapter))
            case .auth, .extension, .rpcHandler:
                // 본 PR 범위 밖. plugin type 별 RPC variant 가 도입되면 추가.
                logger.warning("InProcessLoader: unsupported export type (auth/extension/rpcHandler) in bundle \(manifest.id), skipping")
            @unknown default:
                logger.warning("InProcessLoader: unknown export type in bundle \(manifest.id), skipping")
            }
        }

        loadedBundles[manifest.id] = bundleClass
        logger.info("InProcessLoader: loaded bundle \(manifest.id) with \(proxies.count) proxy(s)")

        return LoadedPluginExports(
            bundleId: manifest.id,
            bundleClass: bundleClass,
            manifest: manifest,
            proxies: proxies,
            accessor: nil
        )
    }

    func unload(bundleId: String) async {
        guard let bundleClass = loadedBundles.removeValue(forKey: bundleId) else {
            return
        }
        do {
            try bundleClass.deinitialize()
            logger.info("InProcessLoader: unloaded bundle \(bundleId)")
        } catch {
            logger.error("InProcessLoader: deinitialize failed for \(bundleId): \(error)")
        }
    }
}
