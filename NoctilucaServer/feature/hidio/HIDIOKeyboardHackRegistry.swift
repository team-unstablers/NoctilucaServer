//
//  HIDIOKeyboardHackRegistry.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/14/26.
//

import NoctilucaPluginKit
import NoctilucaPluginKitHostCore

/// 등록된 keyboard hack 의 RPC proxy + 캐시된 metadata.
///
/// `desiredKeyEvents` 는 RPC mirror 의 async method 라서 매 키 입력마다
/// 다시 묻을 수 없다. 등록 시점에 한 번 받아서 캐시한다.
struct RegisteredKeyboardHack: Sendable {
    let id: String
    let proxy: any KeyboardHackPluginV1RPC
    let desiredKeyEvents: Set<NoctilucaPluginKit.LinuxKeycode>
}

/// 서버에 등록된 `KeyboardHackPluginV1RPC` 들을 보관하는 actor.
///
/// in-process (`InProcessLoader`) 와 XPC (`XPCLoader`) 양쪽 경로가 모두
/// `KeyboardHackPluginV1RPC` 로 통일된 surface 를 통해 등록되므로 registry
/// 는 구현체의 격리 여부를 알 필요가 없다.
actor HIDIOKeyboardHackRegistry {
    static let shared = HIDIOKeyboardHackRegistry()

    private var hacks: [String: RegisteredKeyboardHack] = [:]

    func register(_ proxy: any KeyboardHackPluginV1RPC) async {
        do {
            let id = try await proxy.id()
            let events = try await proxy.desiredKeyEvents()
            self.hacks[id] = RegisteredKeyboardHack(
                id: id,
                proxy: proxy,
                desiredKeyEvents: Set(events)
            )
        } catch {
            // RPC failure on registration — skip silently. caller logs.
        }
    }

    func unregister(_ id: String) {
        self.hacks.removeValue(forKey: id)
    }

    /// 현재 등록된 키보드 hack 들의 스냅샷을 반환한다. 값 의미론.
    func snapshot() -> [String: RegisteredKeyboardHack] {
        self.hacks
    }
}
