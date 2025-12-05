//
//  NullAuthPlugin.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

#if DEBUG

import Foundation
import SiriusKit

final class NullAuthPlugin: AuthPlugin {
    static let id = "pl.unstabler.noctiluca.NoctilucaServer.auth.plugin.null"
    static let name = "NullAuthPlugin"
    static let description = "Provides 'NULL' authentication that always succeeds."
    static let author = "Gyuhwan Park <unstabler@unstabler.pl>"
    static let license = "CC0 1.0"
    static let version: UInt32 = 1
    static let displayVersion = NoctilucaMeta.version
    
    static let supportedMethods: Set<AuthMethod> = [.none]
    
    private let logger = NoctilucaLogger(category: "NullAuthPlugin")
    
    func initialize() async throws {
        // do nothing
    }
    
    func deinitialize() throws {
        // do nothing
    }
    
    func allow(_ entry: AllowedAuthMethod) async throws {
        // do nothing
    }
    
    func deny(_ entry: AllowedAuthMethod) async throws {
        // do nothing
    }
    
    func authenticate(using method: SiriusKit.AuthMethod, payload: borrowing Data) async -> Result<uid_t, AuthError> {
        guard method == .none else {
            return .failure(.unsupportedMethod)
        }
        
        return .success(getuid())
    }
}

#endif
