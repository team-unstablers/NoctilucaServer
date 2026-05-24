//
//  RPCHandlerPluginV1Adapter.swift
//  NoctilucaPluginKitHostCore
//
//  Created by Gyuhwan Park on 5/22/26.
//

import Foundation
import NoctilucaPluginKit

/// `any RPCHandlerPluginV1` 을 wrap 하여 `RPCHandlerPluginV1RPC` 로 expose 하는
/// thin forwarding class. host process / in-process loader 양쪽에서 동일하게
/// 사용한다.
public final class RPCHandlerPluginV1Adapter: RPCHandlerPluginV1RPC {
    private let wrapped: any RPCHandlerPluginV1

    public init(wrapping plugin: any RPCHandlerPluginV1) {
        self.wrapped = plugin
    }

    public func id() async throws -> String {
        type(of: wrapped).id
    }

    public func supportedOperations() async throws -> [String] {
        Array(type(of: wrapped).supportedOperations)
    }

    public func onRPCRequest(operation: String, args: [String]) async throws -> RPCResult {
        try await wrapped.onRPCRequest(operation: operation, args: args)
    }
}
