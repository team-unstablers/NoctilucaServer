//
//  PluginBundleAccessor.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 5/18/26.
//

import Foundation
import NoctilucaPluginKit

/// 외부 (XPC 격리) 플러그인 번들의 bundle-level action 액세스 추상화.
///
/// builtin / no-isolate in-process 번들은 `NoctilucaPluginBundle.Type` 을
/// 직접 보유하므로 본 추상화가 불필요하다 — `PluginBundleHandle.bundleClass`
/// 직접 호출. XPC 격리 번들은 process 너머에 있으므로 본 protocol 의
/// 구현체 (`XPCBundleAccessor` 등) 가 `HostControlInterface` proxy 의
/// `bundle_*` forwarding method 를 호출한다.
protocol PluginBundleAccessor: Sendable {
    func supportedActions() async throws -> [NoctilucaPluginBundleAction]
    func dispatchAction(_ action: NoctilucaPluginBundleAction) async throws
}
