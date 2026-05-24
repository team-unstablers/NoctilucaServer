//
//  RPCHandlerPluginV1RPC.swift
//  NoctilucaPluginKitHostCore
//
//  Created by Gyuhwan Park on 5/22/26.
//

import Foundation
import NoctilucaPluginKit
import Shotoku

/// `RPCHandlerPluginV1` 의 host-side wire mirror.
///
/// 외부 SDK 의 `RPCHandlerPluginV1` 은 `static var id` / `static var supportedOperations`
/// / `init()` / instance method 형태이지만, RPC 너머로는 instance-method 형태만
/// 의미가 있으므로 mirror 는 `func id() async` / `func supportedOperations() async`
/// 로 평탄화한다. `Set<String>` 도 wire 호환성을 위해 `[String]` 으로 풀어서 보낸다.
///
/// `onRPCRequest` 의 경우, SDK 의 `RPCRequest` / `RPCResponse` 추상화는 `resolve()`
/// 같은 메서드를 wire 너머로 보낼 수 없기 때문에, mirror 는 처음부터 raw 필드
/// (`operation` / `args`) 와 `RPCResult` 만으로 평탄화된 시그니처를 사용한다.
///
/// host 의 `*Adapter` class 가 `any RPCHandlerPluginV1` 을 wrap 하여 본 protocol
/// 의 instance method 들로 expose 한다.
@RPCInterface
public protocol RPCHandlerPluginV1RPC: Sendable {
    @RPCProcedure
    func id() async throws -> String

    @RPCProcedure
    func supportedOperations() async throws -> [String]

    @RPCProcedure
    func onRPCRequest(operation: String, args: [String]) async throws -> RPCResult
}
