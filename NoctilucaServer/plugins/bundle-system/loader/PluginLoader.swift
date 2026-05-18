//
//  PluginLoader.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 5/17/26.
//

import Foundation
import NoctilucaPluginKit
import NoctilucaPluginKitHostCore

/// 외부 플러그인 번들 (`.nocbundle` 등) 의 로드 결과.
///
/// builtin 번들은 `PluginBundleRegistry.registerBundle(bundleClass:manifest:)`
/// 경로를 그대로 사용하며 `PluginLoader` 를 거치지 않는다.
///
/// `bundleClass` 와 `accessor` 는 mutually exclusive 한 access path 다:
/// - `InProcessLoader` 는 `bundleClass` 만 반환 (process 내 직접 호출 가능).
/// - `XPCLoader` 는 `accessor` 만 반환 (host process 너머 — `HostControlInterface`
///   forwarding 경유).
struct LoadedPluginExports: Sendable {
    let bundleId: String
    let bundleClass: NoctilucaPluginBundle.Type?
    let manifest: any PluginBundleManifest
    let proxies: [LoadedPluginProxy]
    let accessor: PluginBundleAccessor?
}

/// `*RPC` mirror protocol 의 existential 을 case 별로 운반하는 enum.
///
/// 본 PR 범위에서는 `.keyboardHack` 만 구현. `.auth` / `.rpcHandler` /
/// `.extension` 은 추후 별도 마이그레이션 (docs T5 / T6) 에서 추가 예정.
enum LoadedPluginProxy: Sendable {
    case keyboardHack(any KeyboardHackPluginV1RPC)
}

/// 플러그인 번들 로더 추상화.
///
/// - `InProcessLoader`: server process 안에서 `Bundle.load()` 로 dlopen.
///   isolation policy `no-isolate` 가 선언된 (team unstablers 서명) 번들 용.
/// - `XPCLoader`: `NoctilucaPluginKitHost.xpc` 의 별도 process instance 에
///   bundle path 를 위임. `isolate` 정책 (기본) 용.
protocol PluginLoader: Sendable {
    func load(
        url: URL,
        manifest: any PluginBundleManifest
    ) async throws -> LoadedPluginExports

    func unload(bundleId: String) async
}
