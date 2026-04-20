//
//  RemoteSessionManager.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/1/26.
//

import Foundation
import Observation

import SiriusKitClient

@MainActor
@Observable
final class RemoteSessionManager: Sendable {
    static let shared = RemoteSessionManager()

    private(set) var sessions: [UUID: RemoteSession] = [:]

    init() {

    }

    func register(_ session: RemoteSession, forId id: UUID) {
        sessions[id] = session
    }

    func unregister(_ id: UUID) {
        guard sessions.keys.contains(id) else {
            return
        }

        sessions.removeValue(forKey: id)
    }
}
