//
//  NullAuthPlugin.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

import libbcrypt

import SiriusKit
@preconcurrency import NoctilucaPluginKit

final class SimplePasswordAuthPlugin: BuiltInAuthPluginV1 {
    static let metadata = BuiltinPluginBundleExportMetadata(
        id: "app.noctiluca.server.auth.plugin.simple-password",
        displayName: NSLocalizedString("plugins.auth.SimplePasswordAuthPlugin.name", comment: "SimplePasswordAuthPlugin"),
        type: .auth,
        description: NSLocalizedString(
            "plugins.auth.SimplePasswordAuthPlugin.description",
            comment: (
                "Provides password-only authentication using SHA-512 + Bcrypt.\n" +
                
                // KO: 이 플러그인은 Ricardo Garcia (@rg3) 님이 작성하신 libbcrypt를 기반으로 합니다.
                //     @rg3 님의 libbcrypt는 CC0-1.0 라이선스 하에 배포되고 있으며, team unstablers Inc. 에서 Noctiluca Server 개발을 위해 포크한 버전은 https://github.com/team-unstablers/libbcrypt/ 에서 확인하실 수 있습니다.
                "This plugin is based on libbcrypt written by Ricardo Garcia (@rg3).\n" +
                "@rg3's libbcrypt is distributed under the CC0-1.0 license, and the forked version by team unstablers Inc. for Noctiluca Server development can be found at https://github.com/team-unstablers/libbcrypt ."
            )
        )
    )
    
    
    static let id = "app.noctiluca.server.auth.plugin.simple-password"
    
    static let name = NSLocalizedString("plugins.auth.SimplePasswordAuthPlugin.name", comment: "SimplePasswordAuthPlugin")
    static let description = NSLocalizedString(
        "plugins.auth.SimplePasswordAuthPlugin.description",
        comment: (
            "Provides password-only authentication using SHA-512 + Bcrypt.\n" +
            
            // KO: 이 플러그인은 Ricardo Garcia (@rg3) 님이 작성하신 libbcrypt를 기반으로 합니다.
            //     @rg3 님의 libbcrypt는 CC0-1.0 라이선스 하에 배포되고 있으며, team unstablers Inc. 에서 Noctiluca Server 개발을 위해 포크한 버전은 https://github.com/team-unstablers/libbcrypt/ 에서 확인하실 수 있습니다.
            "This plugin is based on libbcrypt written by Ricardo Garcia (@rg3).\n" +
            "@rg3's libbcrypt is distributed under the CC0-1.0 license, and the forked version by team unstablers Inc. for Noctiluca Server development can be found at https://github.com/team-unstablers/libbcrypt ."
        )
    )
    static let authors = [
        "Gyuhwan Park <unstabler@unstabler.pl>"
    ]
    static let license: SoftwareLicense = NoctilucaMeta.license
    static let version: UInt32 = 1
    static let displayVersion = NoctilucaMeta.version
    
    static let supportedMethods: Set<NoctilucaPluginKit.AuthMethod> = [.simplePassword]
    
    private let logger = NoctilucaLogger(category: "SimplePasswordAuthPlugin")
    
    private var allowedHashes: [Data] = []
    
    var hasAllowedEntries: Bool {
        return !allowedHashes.isEmpty
    }
    
    func allow(_ entry: AuthEntry) async throws {
        guard entry.identifier == "bcrypt+sha512" else {
            logger.error("allow(): expected identifier 'bcrypt+sha512', got '\(entry.identifier)'")
            return
        }
        
        guard let hash = entry.data,
              hash.count == Int(BCRYPT_HASHSIZE)
        else {
            logger.error("allow(): invalid hash data, this entry will be ignored")
            return
        }
        
        allowedHashes.append(hash)
    }
    
    func deny(_ entry: AuthEntry) async throws {
        guard entry.identifier == "bcrypt+sha512" else {
            logger.error("deny(): expected identifier 'bcrypt+sha512', got '\(entry.identifier)'")
            return
        }
        
        guard let hash = entry.data,
              hash.count == Int(BCRYPT_HASHSIZE)
        else {
            logger.error("deny(): invalid hash data, this entry will be ignored")
            return
        }
        
        allowedHashes.removeAll { $0 == hash }
    }
    
    func authenticate(using method: NoctilucaPluginKit.AuthMethod, payload: borrowing Data, nonce: Data) async -> Result<uid_t, AuthError> {
        guard method == .simplePassword else {
            return .failure(.unsupportedMethod)
        }

        do {
            var payloadCopy = copy payload
            defer { payloadCopy.zeroize() }
            var digest = try await Bcrypt.sha512Async(value: payloadCopy)
            defer { digest.zeroize() }
            for hash in allowedHashes {
                do {
                    if try await Bcrypt.verifyAsync(password: digest, hash: hash) {
                        return .success(getuid())
                    }
                } catch {
                    continue
                }
            }
        } catch {
            logger.error("authenticate(): error during verification: \(error.localizedDescription)")

            return .failure(.authenticationFailed(error))
        }

        return .failure(.authenticationFailed(nil))
    }
}
