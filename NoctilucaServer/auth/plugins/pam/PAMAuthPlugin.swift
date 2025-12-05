//
//  PAMAuthPlugin.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation
import SiriusKit

final class PAMAuthPlugin: AuthPlugin {
    static let id = "pl.unstabler.noctiluca.NoctilucaServer.auth.plugin.pam"
    static let name = "PAMAuthPlugin"
    static let description = "Provides UNIX PAM-based username-password authentication."
    static let author = "Gyuhwan Park <unstabler@unstabler.pl>"
    static let license = ""
    static let version: UInt32 = 1
    static let displayVersion = NoctilucaMeta.version
    
    static let supportedMethods: Set<AuthMethod> = [.password]
    
    private let logger = NoctilucaLogger(category: "PAMAuthPlugin")
    
    private var allowedUsers: Set<String> = []
    private var allowedGroups: Set<String> = []
    
    func initialize() async throws {
        allowedUsers = []
        allowedGroups = []
        
        logger.trace("initialize(): PAMAuthPlugin initialized")
    }
    
    func deinitialize() throws {
        allowedUsers = []
        allowedGroups = []
        
        logger.trace("deinitialize(): PAMAuthPlugin deinitialized")
    }
    
    func allow(_ entry: AllowedAuthMethod) async throws {
        guard case .password(let item) = entry else {
            logger.warning("allow(): Unsupported AllowedAuthMethod entry: \(entry)")
            return
        }
        
        switch item {
        case .group(let name):
            logger.trace("allow(): Allowed PAM authentication for group: \(name)")
            allowedGroups.insert(name)
        case .user(let name):
            logger.trace("allow(): Allowed PAM authentication for user: \(name)")
            allowedUsers.insert(name)
        }
    }
    
    func deny(_ entry: AllowedAuthMethod) async throws {
        guard case .password(let item) = entry else {
            logger.warning("deny(): Unsupported AllowedAuthMethod entry: \(entry)")
            return
        }
        
        switch item {
        case .group(let name):
            logger.trace("deny(): Denied PAM authentication for group: \(name)")
            allowedGroups.remove(name)
        case .user(let name):
            logger.trace("deny(): Denied PAM authentication for user: \(name)")
            allowedUsers.remove(name)
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
    
    func authenticate(using method: SiriusKit.AuthMethod, payload: borrowing Data) async -> Result<uid_t, AuthError> {
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
