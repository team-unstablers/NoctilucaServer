//
//  PAMAuthClientPlugin.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

final class PAMAuthClientPlugin: ClientAuthPluginV1 {
    static let id = "pl.unstabler.noctiluca.NoctilucaClient.auth.pam"
    static let name = "PAM Auth"
    static let description = "UNIX PAM username-password authentication"

    static let supportedMethods: Set<ClientAuthMethod> = [.password]

    init() {}

    func payload(for entry: ClientAuthEntry) throws -> Data {
        guard entry.method == .password else {
            throw ClientAuthPluginError.unsupportedEntry
        }

        guard case .password(let username, let password) = entry.payload else {
            throw ClientAuthPluginError.invalidPayload
        }

        return PAMAuthPayload.payload(username: username, password: password)
    }
}
