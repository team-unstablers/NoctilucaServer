//
//  KeyboardHackPluginV1RPC.swift
//  NoctilucaPluginKitHostCore
//
//  Created by Gyuhwan Park on 5/17/26.
//

import Foundation
import NoctilucaPluginKit
import Shotoku

/// `KeyboardHackPluginV1` 의 host-side wire mirror.
///
/// 외부 SDK 의 `KeyboardHackPluginV1` 은 `static var id` / `static var desiredKeyEvents`
/// / `init()` / instance method 형태이지만, RPC 너머로는 instance-method 형태만
/// 의미가 있으므로 mirror 는 `func id() async` / `func desiredKeyEvents() async`
/// 로 평탄화한다. `Set<LinuxKeycode>` 도 wire 호환성을 위해 `[LinuxKeycode]` 로
/// 풀어서 보낸다.
///
/// host 의 `*Adapter` class 가 `any KeyboardHackPluginV1` 을 wrap 하여 본 protocol
/// 의 instance method 들로 expose 한다.
@RPCInterface
public protocol KeyboardHackPluginV1RPC: Sendable {
    @RPCProcedure
    func id() async throws -> String

    @RPCProcedure
    func desiredKeyEvents() async throws -> [LinuxKeycode]

    @RPCProcedure
    func onKeyDown(_ keyCode: LinuxKeycode) async throws -> KeyboardHackResult

    @RPCProcedure
    func onKeyUp(_ keyCode: LinuxKeycode) async throws -> KeyboardHackResult
}
