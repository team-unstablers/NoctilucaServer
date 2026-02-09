//
//  SimplePasswordAuthClientPlugin.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

final class SimplePasswordAuthClientPlugin: ClientAuthPluginV1 {
    static let id = "app.noctiluca.client.auth.simple-password"
    static let name = "Simple Password Auth"
    static let description = "Password-only authentication"

    static let supportedMethods: Set<ClientAuthMethod> = [.simplePassword]

    init() {}

    func payload(for entry: ClientAuthEntry, nonce: Data) throws -> Data {
        guard entry.method == .simplePassword else {
            throw ClientAuthPluginError.unsupportedEntry
        }

        guard case .simplePassword(let password) = entry.payload else {
            throw ClientAuthPluginError.invalidPayload
        }

        return Data(password.utf8)
    }
}
