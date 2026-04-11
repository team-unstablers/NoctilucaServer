//
//  HIDIOKeyboardHackRegistry.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/14/26.
//

import NoctilucaPluginKit

/// 서버에 등록된 `KeyboardHackPluginV1` 구현체들을 보관하는 actor.
///
/// 등록(`register`)은 서버 기동 시점에 `PluginBundleRegistry` 가 번들을 로드하면서
/// 한 번 호출되고, 조회(`snapshot`)는 HIDIO 세션이 `KeyboardSetupEvent` 를 처리할 때마다
/// `HIDIOChannelState` 에서 호출된다. 두 경로가 서로 다른 async 컨텍스트에서 일어나므로
/// Swift 6 strict concurrency 환경에서 공유 가능한 레지스트리는 actor 로 격리한다.
actor HIDIOKeyboardHackRegistry {
    static let shared = HIDIOKeyboardHackRegistry()

    private var hacks: [String: KeyboardHackPluginV1] = [:]

    func register(_ plugin: KeyboardHackPluginV1) {
        self.hacks[type(of: plugin).id] = plugin
    }

    func unregister(_ id: String) {
        self.hacks.removeValue(forKey: id)
    }

    /// 현재 등록된 플러그인 목록의 스냅샷을 반환한다.
    ///
    /// 딕셔너리는 값 타입이므로 actor 경계를 넘어 복사되며, 호출자는 반환값을
    /// 자유롭게 사용할 수 있다. 값(플러그인 인스턴스) 자체는 공유 참조이므로
    /// 구현체가 Sendable 을 적합하게 구현해야 한다.
    func snapshot() -> [String: KeyboardHackPluginV1] {
        self.hacks
    }
}
