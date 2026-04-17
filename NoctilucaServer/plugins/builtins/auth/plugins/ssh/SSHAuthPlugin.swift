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

typealias SSHPublicKey = Xuanxue.PublicKey

actor SSHAuthPlugin: BuiltInAuthPluginV1 {
    static let metadata = BuiltinPluginBundleExportMetadata(
        id: "app.noctiluca.server.auth.plugin.ssh",
        displayName: NSLocalizedString("plugins.auth.SSHAuthPlugin.name", comment: "SSHAuthPlugin"),
        type: .auth,
        description: NSLocalizedString(
            "plugins.auth.SSHAuthPlugin.description",
            comment: "Provides SSH public key authentication."
        )
    )
    
    
    static let id = "app.noctiluca.server.auth.plugin.ssh"
    
    static let name = NSLocalizedString("plugins.auth.SSHAuthPlugin.name", comment: "SSHAuthPlugin")
    static let description = NSLocalizedString(
        "plugins.auth.SSHAuthPlugin.description",
        comment: "Provides SSH public key authentication."
    )
    static let authors = [
        "Gyuhwan Park <unstabler@unstabler.pl>"
    ]
    
    static let license: SoftwareLicense = NoctilucaMeta.license
    static let version: UInt32 = 1
    static let displayVersion = NoctilucaMeta.version
    
    static let supportedMethods: Set<NoctilucaPluginKit.AuthMethod> = [.sshKey]
    
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
