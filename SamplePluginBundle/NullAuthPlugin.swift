//
//  NullAuthPlugin.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

import NoctilucaPluginKit

extension AuthMethod {
    static let none = AuthMethod(rawValue: "com.example.authmethod.none")
}

final class NullAuthPlugin: AuthPluginV1 {
    static let id = "app.noctiluca.server.plugin.test.null"
    
    static let name = NSLocalizedString("plugins.auth.NullAuthPlugin.name", comment: "NullAuthPlugin")
    static let description = NSLocalizedString("plugins.auth.NullAuthPlugin.description", comment: "Provides 'NULL' authentication that always succeeds.")
    static let authors = [
        "Gyuhwan Park <unstabler@unstabler.pl>"
    ]
    static let license: SoftwareLicense = .cc0
    static let version: UInt32 = 1
    static let displayVersion = "1.0.0"
    
    static let supportedMethods: Set<AuthMethod> = [.none]
    
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
