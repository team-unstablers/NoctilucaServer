//
//  SimplePasswordAuthClientPlugin.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

import Xuanxue

typealias SSHPrivateKey = Xuanxue.PrivateKey

final class SSHAuthClientPlugin: ClientAuthPluginV1 {
    static let id = "app.noctiluca.client.auth.ssh"
    static let name = "SSH Auth Plugin"
    static let description = "provides SSH Key-based authentication."

    static let supportedMethods: Set<ClientAuthMethod> = [.sshKey]

    init() {}

    func payload(for entry: ClientAuthEntry, nonce: Data) throws -> Data {
        guard entry.method == .sshKey else {
            throw ClientAuthPluginError.unsupportedEntry
        }

        guard case .sshKey(_, let privateKeyData) = entry.payload,
              let privateKeyString = String(data: privateKeyData, encoding: .utf8)
        else {
            throw ClientAuthPluginError.invalidPayload
        }
        
        let privateKey = try SSHPrivateKey(sshString: privateKeyString)
        
        return privateKey.sign(nonce)
    }
}
