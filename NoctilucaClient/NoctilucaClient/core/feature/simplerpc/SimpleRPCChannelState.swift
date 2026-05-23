//
//  SimpleRPCChannelState.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 5/23/26.
//

import Foundation
import SiriusKitClient

/// SimpleRPCChannel 의 mutable state 를 actor isolation 으로 보호합니다.
actor SimpleRPCChannelState {
    typealias PendingHandler = @Sendable (Result<SimpleRPCResponse, Error>) -> Void

    private var pendingRequests: [UUID: PendingHandler] = [:]

    func registerPendingRequest(_ id: UUID, handler: @escaping PendingHandler) {
        pendingRequests[id] = handler
    }

    @discardableResult
    func dispatchPendingRequest(_ id: UUID, response: SimpleRPCResponse) -> Bool {
        guard let handler = pendingRequests.removeValue(forKey: id) else {
            return false
        }
        handler(.success(response))
        return true
    }

    @discardableResult
    func failPendingRequest(_ id: UUID, error: Error) -> Bool {
        guard let handler = pendingRequests.removeValue(forKey: id) else {
            return false
        }
        handler(.failure(error))
        return true
    }

    func removePendingRequest(_ id: UUID) {
        pendingRequests.removeValue(forKey: id)
    }

    func cancelAllPending(with error: Error) {
        let pending = pendingRequests
        pendingRequests.removeAll()
        for (_, handler) in pending {
            handler(.failure(error))
        }
    }
}
