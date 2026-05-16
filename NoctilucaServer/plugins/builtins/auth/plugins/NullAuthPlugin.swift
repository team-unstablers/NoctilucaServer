//
//  NullAuthPlugin.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

#if DEBUG

import Foundation

import NoctilucaPluginKit

actor NullAuthPlugin: BuiltInAuthPluginV1 {
    static let id = "app.noctiluca.server.auth.plugin.null"

    static let supportedMethods: Set<AuthMethod> = [.null]
    
    private let logger = NoctilucaLogger(category: "NullAuthPlugin")
    
    var hasAllowedEntries: Bool {
        return true
    }
    
    func allow(_ entry: AuthEntry) async throws {
        // do nothing
    }
    
    func deny(_ entry: AuthEntry) async throws {
        // do nothing
    }
    
    func authenticate(using method: AuthMethod, payload: borrowing Data, nonce: Data) async -> Result<uid_t, AuthError> {
        guard method == .none else {
            return .failure(.unsupportedMethod)
        }
        
        return .success(getuid())
    }
}

#endif
