//
//  SSHAuthPlugin.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/18/26.
//

import Foundation

import Xuanxue

import SiriusKit
@preconcurrency import NoctilucaPluginKit
import NoctilucaPluginKitHostCore

typealias SSHPublicKey = Xuanxue.PublicKey

actor SSHAuthPlugin: BuiltInAuthPluginV1 {
    static let id = "app.noctiluca.server.auth.plugin.ssh"

    static let supportedMethods: Set<NoctilucaPluginKit.AuthMethod> = [.sshKey]

    static let manifest: NocPluginManifest = .auth(
        BuiltinAuthPluginManifest(
            id: id,
            name: NSLocalizedString("plugins.auth.SSHAuthPlugin.name", comment: "SSHAuthPlugin"),
            pluginDescription: NSLocalizedString(
                "plugins.auth.SSHAuthPlugin.description",
                comment: "Provides SSH public key authentication."
            ),
            authors: [
                "Gyuhwan Park <unstabler@unstabler.pl>"
            ],
            license: NoctilucaMeta.license,
            version: 1,
            displayVersion: NoctilucaMeta.version,
            supportedMethods: supportedMethods.map(\.rawValue)
        )
    )
    
    private let logger = NoctilucaLogger(category: "SSHAuthPlugin")
    
    private var authorizedKeys: [SSHPublicKey] = []
    
    var hasAllowedEntries: Bool {
        return !authorizedKeys.isEmpty
    }
    
    func allow(_ entry: AuthEntry) async throws {
        guard let data = entry.data,
              let publicKeyString = String(data: data, encoding: .utf8)
        else {
            logger.error("allow(): invalid data for SSH public key")
            return
        }
        
        let publicKey = try SSHPublicKey(sshString: publicKeyString)
        authorizedKeys.append(publicKey)
    }
    
    func deny(_ entry: AuthEntry) async throws {
        guard let data = entry.data,
              let publicKeyString = String(data: data, encoding: .utf8)
        else {
            logger.error("allow(): invalid data for SSH public key")
            return
        }
        
        let publicKey = try SSHPublicKey(sshString: publicKeyString)
        authorizedKeys.removeAll { $0 == publicKey }
    }
    
    func authenticate(using method: NoctilucaPluginKit.AuthMethod, payload: borrowing Data, nonce: Data) async -> Result<uid_t, AuthError> {
        guard method == .sshKey else {
            return .failure(.unsupportedMethod)
        }
        
        for key in authorizedKeys {
            if key.verify(payload, for: nonce) {
                return .success(getuid()) // TODO: 실제 uid 매핑 구현
            }
        }
        
        
        return .failure(.authenticationFailed(nil))
    }
}
