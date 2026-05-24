//
//  SimpleRPCHandlerRegistry.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 5/22/26.
//

import SiriusKit

import NoctilucaPluginKit
import NoctilucaPluginKitHostCore

/// 등록된 RPC handler 의 RPC proxy + 캐시된 metadata.
///
/// `supportedOperations` 는 RPC mirror 의 async method 라서 매 요청마다 다시
/// 묻을 수 없다. 등록 시점에 한 번 받아서 캐시한다.
struct RegisteredRPCHandler: Sendable {
    let id: String
    let proxy: any RPCHandlerPluginV1RPC
    let supportedOperations: Set<String>
}

/// 서버에 등록된 `RPCHandlerPluginV1RPC` 들을 보관하는 actor.
///
/// in-process (`InProcessLoader`) 와 XPC (`XPCLoader`) 양쪽 경로가 모두
/// `RPCHandlerPluginV1RPC` 로 통일된 surface 를 통해 등록되므로 registry 는
/// 구현체의 격리 여부를 알 필요가 없다.
///
/// dispatch 는 `operation` 식별자 기반으로 단일 핸들러로 라우팅된다. 동일한
/// operation 을 두 플러그인이 요구하는 경우, 먼저 등록된 쪽이 우선권을 갖고
/// 이후 등록은 해당 operation 에 한해 무시된다.
actor SimpleRPCHandlerRegistry {
    static let shared = SimpleRPCHandlerRegistry()

    private let logger = NoctilucaLogger(category: "SimpleRPCHandlerRegistry")

    /// pluginId → 등록 레코드.
    private var handlers: [String: RegisteredRPCHandler] = [:]

    /// operation → pluginId. 디스패치 fast path.
    private var operationRouting: [String: String] = [:]

    func register(_ proxy: any RPCHandlerPluginV1RPC) async {
        let id: String
        let rawOperations: [String]
        do {
            id = try await proxy.id()
            rawOperations = try await proxy.supportedOperations()
        } catch {
            logger.error("failed to query RPC handler metadata during registration: \(error)")
            return
        }

        if self.handlers[id] != nil {
            logger.warning("RPC handler '\(id)' is already registered; ignoring duplicate registration")
            return
        }

        var acceptedOperations: Set<String> = []
        for operation in rawOperations {
            if Self.isReservedNamespace(operation) {
                logger.warning("plugin '\(id)' declared reserved operation '\(operation)'; ignored")
                continue
            }

            if let existing = operationRouting[operation] {
                logger.warning("operation '\(operation)' is already claimed by '\(existing)'; '\(id)' will not handle it")
                continue
            }

            operationRouting[operation] = id
            acceptedOperations.insert(operation)
        }

        self.handlers[id] = RegisteredRPCHandler(
            id: id,
            proxy: proxy,
            supportedOperations: acceptedOperations
        )

        logger.debug("registered RPC handler '\(id)' for \(acceptedOperations.count) operation(s)")
    }

    func unregister(_ id: String) {
        guard let registered = self.handlers.removeValue(forKey: id) else {
            return
        }
        for operation in registered.supportedOperations {
            if operationRouting[operation] == id {
                operationRouting.removeValue(forKey: operation)
            }
        }
    }

    /// operation 으로 등록된 핸들러를 찾아 dispatch 한다.
    ///
    /// 매칭되는 핸들러가 없으면 `.failure(.notSupported)`, 핸들러가 throw 하면
    /// `.failure(.internalError)` 를 반환한다.
    func dispatch(operation: String, args: [String]) async -> RPCResult {
        if Self.isReservedNamespace(operation) {
            logger.warning("refused to dispatch reserved operation '\(operation)'")
            return .failure(.notSupported)
        }

        guard let handlerId = operationRouting[operation],
              let registered = self.handlers[handlerId] else {
            return .failure(.notSupported)
        }

        do {
            return try await registered.proxy.onRPCRequest(operation: operation, args: args)
        } catch {
            logger.error("plugin '\(handlerId)' threw on operation '\(operation)': \(error)")
            return .failure(.internalError)
        }
    }

    /// 현재 등록된 RPC handler 들의 스냅샷을 반환한다. 값 의미론.
    func snapshot() -> [String: RegisteredRPCHandler] {
        self.handlers
    }

    private static func isReservedNamespace(_ operation: String) -> Bool {
        return operation.hasPrefix("sirius.")
            || operation.hasPrefix("so.libsirius.")
    }
}
