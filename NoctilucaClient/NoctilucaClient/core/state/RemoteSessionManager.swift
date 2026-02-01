//
//  RemoteSessionManager.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/1/26.
//

import Foundation
import Combine

import SiriusKitClient

class RemoteSessionManager: ObservableObject {
    static let shared = RemoteSessionManager()
    
    @Published
    private(set) var sessions: [UUID: RemoteSession] = [:]
    
    init() {
        
    }
    
    @MainActor
    func register(_ session: RemoteSession, forId id: UUID) {
        sessions[id] = session
    }
    
    @MainActor
    func unregister(_ id: UUID) {
        guard sessions.keys.contains(id) else {
            return
        }
        
        sessions.removeValue(forKey: id)
    }
}

