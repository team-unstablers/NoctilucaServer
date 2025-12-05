//
//  NullAuthPlugin.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

#if DEBUG

import Foundation

import NoctilucaPluginKit

final class NullAuthPlugin: AuthPluginV1 {
    static let id = "pl.unstabler.noctiluca.NoctilucaServer.auth.plugin.null"
    static let name = "NullAuthPlugin"
    static let description = "Provides 'NULL' authentication that always succeeds."
    static let authors = [
        "Gyuhwan Park <unstabler@unstabler.pl>"
    ]
    static let license: SoftwareLicense = NoctilucaMeta.license
    static let version: UInt32 = 1
    static let displayVersion = NoctilucaMeta.version
    
    static let supportedMethods: Set<AuthMethod> = [.none]
    
    private let logger = NoctilucaLogger(category: "NullAuthPlugin")
    
    func allow(_ entry: AuthEntry) async throws {
        // do nothing
    }
    
    func deny(_ entry: AuthEntry) async throws {
        // do nothing
    }
    
    func authenticate(using method: AuthMethod, payload: borrowing Data) async -> Result<uid_t, AuthError> {
        guard method == .none else {
            return .failure(.unsupportedMethod)
        }
        
        return .success(getuid())
    }
}

#endif
