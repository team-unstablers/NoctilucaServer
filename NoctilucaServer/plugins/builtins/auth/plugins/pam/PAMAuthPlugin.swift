//
//  PAMAuthPlugin.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

import SiriusKit
@preconcurrency import NoctilucaPluginKit

actor PAMAuthPlugin: BuiltInAuthPluginV1 {
    static let id = "app.noctiluca.server.plugins.auth.pam"

    static let supportedMethods: Set<NoctilucaPluginKit.AuthMethod> = [.password]

    static let manifest: NocPluginManifest = .auth(
        BuiltinAuthPluginManifest(
            id: id,
            name: NSLocalizedString("plugins.auth.PAMAuthPlugin.name", comment: "PAMAuthPlugin"),
            pluginDescription: NSLocalizedString("plugins.auth.PAMAuthPlugin.description", comment: "Provides UNIX PAM-based username-password authentication."),
            authors: [
                "Gyuhwan Park <unstabler@unstabler.pl>"
            ],
            license: NoctilucaMeta.license,
            version: 1,
            displayVersion: NoctilucaMeta.version,
            supportedMethods: supportedMethods.map(\.rawValue)
        )
    )
    
    private static let authQueue = DispatchQueue(
        label: "app.noctiluca.server.auth.pam",
        qos: .userInitiated
    )

    private let logger = NoctilucaLogger(category: "PAMAuthPlugin")
    
    private var allowedUsers: Set<String> = []
    private var allowedGroups: Set<String> = []
    
    var hasAllowedEntries: Bool {
        return !allowedUsers.isEmpty || !allowedGroups.isEmpty
    }
    
    func allow(_ entry: AuthEntry) async throws {
        guard entry.method == .password else {
            logger.warning("allow(): Unsupported entry: \(entry)")
            return
        }
        
        if entry.identifier.hasPrefix("group:") {
            let groupName = String(entry.identifier.dropFirst("group:".count))
            allowedGroups.insert(groupName)
        } else if entry.identifier.hasPrefix("user:") {
            let userName = String(entry.identifier.dropFirst("user:".count))
            allowedUsers.insert(userName)
        } else {
            logger.warning("allow(): Invalid entry identifier: \(entry.identifier)")
            return
        }
    }
    
    func deny(_ entry: AuthEntry) async throws {
        guard entry.method == .password else {
            logger.warning("deny(): Unsupported entry: \(entry)")
            return
        }
        
        if entry.identifier.hasPrefix("group:") {
            let groupName = String(entry.identifier.dropFirst("group:".count))
            allowedGroups.remove(groupName)
        } else if entry.identifier.hasPrefix("user:") {
            let userName = String(entry.identifier.dropFirst("user:".count))
            allowedUsers.remove(userName)
        } else {
            logger.warning("deny(): Invalid entry identifier: \(entry.identifier)")
            return
        }
    }
    
    internal func isEntryAllowed(_ entry: PasswdEntry) throws -> Bool {
        if let groupName = try Passwd.__getgrgid_gr_name(entry.gid),
           self.allowedGroups.contains(groupName)
        {
            return true
        }


        return self.allowedUsers.contains(entry.username)
    }
    
    func authenticate(using method: NoctilucaPluginKit.AuthMethod, payload: borrowing Data, nonce: Data) async -> Result<uid_t, AuthError> {
        guard method == .password else {
            return .failure(.unsupportedMethod)
        }

        guard PAMAuthPayload.validate(payload: payload),
              let username = String(data: PAMAuthPayload.username(from: payload), encoding: .utf8)
        else {
            return .failure(.invalidPayload)
        }

        var password = PAMAuthPayload.password(from: payload)
        defer { password.zeroize() }

        let passwd: PasswdEntry
        do {
            guard let entry = try Passwd.__getpwnam(username),
                  try self.isEntryAllowed(entry)
            else {
                return .failure(.authenticationFailed(nil))
            }
            passwd = entry
        } catch {
            logger.error("authenticate(): Passwd lookup failed for user '\(username)': \(error)")
            return .failure(.authenticationFailed(nil))
        }

        do {
            logger.debug("authenticate(): Authenticating user '\(username)' via PAM")

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                Self.authQueue.async {
                    do {
                        try PAMAuthPluginObjC.authenticate(username, password: password)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }

            logger.info("authenticate(): PAM authentication succeeded for user '\(username)' (uid: \(passwd.uid))")

            return .success(passwd.uid)
        } catch {
            logger.error("authenticate(): PAM authentication failed for user '\(username)': \(error.localizedDescription)")

            return .failure(.authenticationFailed(error))
        }
    }
}

internal struct PAMAuthPayload {
    static func __usernameLength(from payload: borrowing Data) -> UInt32 {
        payload.subdata(in: 0..<4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }
    
    static func __passwordLength(from payload: borrowing Data) -> UInt32 {
        payload.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }
    
    static func validate(payload: borrowing Data) -> Bool {
        // [uint32_t: username length] [uint32_t: password length] [username bytes] [password bytes]
        
        guard payload.count >= 8 else {
            return false
        }
        
        let usernameLength = __usernameLength(from: payload)
        let passwordLength = __passwordLength(from: payload)
        
        return payload.count == 8 + Int(usernameLength) + Int(passwordLength)
    }
    
    static func username(from payload: borrowing Data) -> Data {
        let usernameLength = __usernameLength(from: payload)
        let usernameData = payload.subdata(in: 8..<(8 + Int(usernameLength)))
        
        return usernameData
    }
    
    static func password(from payload: borrowing Data) -> Data {
        let usernameLength = __usernameLength(from: payload)
        let passwordLength = __passwordLength(from: payload)
        let passwordData = payload.subdata(in: (8 + Int(usernameLength))..<(8 + Int(usernameLength) + Int(passwordLength)))
        
        return passwordData
    }
}
