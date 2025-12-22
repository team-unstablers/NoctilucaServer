//
//  PAMAuthPlugin.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

import SiriusKit
import NoctilucaPluginKit

final class PAMAuthPlugin: BuiltInAuthPluginV1 {
    static let metadata = BuiltinPluginBundleExportMetadata(
        id: "pl.unstabler.noctiluca.NoctilucaServer.plugins.auth.pam",
        displayName: NSLocalizedString("plugins.auth.PAMAuthPlugin.name", comment: "PAMAuthPlugin"),
        type: .auth,
        description: NSLocalizedString("plugins.auth.PAMAuthPlugin.description", comment: "Provides UNIX PAM-based username-password authentication.")
    )
    
    static let id = "pl.unstabler.noctiluca.NoctilucaServer.plugins.auth.pam"
    static let name = NSLocalizedString("plugins.auth.PAMAuthPlugin.name", comment: "PAMAuthPlugin")
    static let description = NSLocalizedString("plugins.auth.PAMAuthPlugin.description", comment: "Provides UNIX PAM-based username-password authentication.")
    static let authors = [
        "Gyuhwan Park <unstabler@unstabler.pl>"
    ]
    static let license: SoftwareLicense = NoctilucaMeta.license
    static let version: UInt32 = 1
    static let displayVersion = NoctilucaMeta.version
    
    static let supportedMethods: Set<NoctilucaPluginKit.AuthMethod> = [.password]
    
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
    
    internal func isEntryAllowed(_ entry: PasswdEntry) -> Bool {
        if let groupName = Passwd.__getgrgid_gr_name(entry.gid),
           self.allowedGroups.contains(groupName)
        {
            return true
        }
        
        
        return self.allowedUsers.contains(entry.username)
    }
    
    func authenticate(using method: NoctilucaPluginKit.AuthMethod, payload: borrowing Data) async -> Result<uid_t, AuthError> {
        guard method == .password else {
            return .failure(.unsupportedMethod)
        }
        
        guard PAMAuthPayload.validate(payload: payload),
              let username = String(data: PAMAuthPayload.username(from: payload), encoding: .utf8)
        else {
            return .failure(.invalidPayload)
        }
        
        let password = PAMAuthPayload.password(from: payload)
        
        guard let passwd = Passwd.__getpwnam(username),
              self.isEntryAllowed(passwd)
        else {
            return .failure(.authenticationFailed(nil))
        }
        
        do {
            logger.debug("authenticate(): Authenticating user '\(username)' via PAM")
            try PAMAuthPluginObjC.authenticate(username, password: password)
            
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
