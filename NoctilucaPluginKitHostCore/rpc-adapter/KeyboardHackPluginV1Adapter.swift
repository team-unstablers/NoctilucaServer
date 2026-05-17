//
//  KeyboardHackPluginV1Adapter.swift
//  NoctilucaPluginKitHostCore
//
//  Created by Gyuhwan Park on 5/17/26.
//

import Foundation
import NoctilucaPluginKit

/// `any KeyboardHackPluginV1` 을 wrap 하여 `KeyboardHackPluginV1RPC` 로 expose
/// 하는 thin forwarding class. host process / in-process loader 양쪽에서 동일
/// 하게 사용한다.
public final class KeyboardHackPluginV1Adapter: KeyboardHackPluginV1RPC {
    private let wrapped: any KeyboardHackPluginV1

    public init(wrapping plugin: any KeyboardHackPluginV1) {
        self.wrapped = plugin
    }

    public func id() async throws -> String {
        type(of: wrapped).id
    }

    public func desiredKeyEvents() async throws -> [LinuxKeycode] {
        Array(type(of: wrapped).desiredKeyEvents)
    }

    public func onKeyDown(_ keyCode: LinuxKeycode) async throws -> KeyboardHackResult {
        await wrapped.onKeyDown(keyCode)
    }

    public func onKeyUp(_ keyCode: LinuxKeycode) async throws -> KeyboardHackResult {
        await wrapped.onKeyUp(keyCode)
    }
}
