//
//  AuthMethod.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/27/25.
//

import Foundation
import SiriusKit

enum PAMAuthAllowlistItem: Codable {
    case group(name: String)
    case user(name: String)
    
    enum CodingKeys: String, CodingKey {
        case type
        case name
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let name = try container.decode(String.self, forKey: .name)
        
        switch type {
        case "group":
            self = .group(name: name)
        case "user":
            self = .user(name: name)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid type value")
        }
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .group(let name):
            try container.encode("group", forKey: .type)
            try container.encode(name, forKey: .name)
        case .user(let name):
            try container.encode("user", forKey: .type)
            try container.encode(name, forKey: .name)
        }
    }
}

enum AuthMethod: Codable {
#if DEBUG
    case none
#endif
    
    case password(allows: PAMAuthAllowlistItem)
    case simplePassword(bcryptHash: String)
    case sshKey(publicKey: String)
    
    enum CodingKeys: String, CodingKey {
        case type
        case args
    }
    
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        
        switch type {
#if DEBUG
        case "none":
            self = .none
#endif
        case "password":
            let allows = try container.decode(PAMAuthAllowlistItem.self, forKey: .args)
            self = .password(allows: allows)
        case "simplePassword":
            let bcryptHash = try container.decode(String.self, forKey: .args)
            self = .simplePassword(bcryptHash: bcryptHash)
        case "sshKey":
            let publicKey = try container.decode(String.self, forKey: .args)
            self = .sshKey(publicKey: publicKey)
        default:
            throw DecodingError.dataCorruptedError(forKey: .type, in: container, debugDescription: "Invalid type value")
        }
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
#if DEBUG
        case .none:
            try container.encode("none", forKey: .type)
#endif
        case .password(let allows):
            try container.encode("password", forKey: .type)
            try container.encode(allows, forKey: .args)
        case .simplePassword(let bcryptHash):
            try container.encode("simplePassword", forKey: .type)
            try container.encode(bcryptHash, forKey: .args)
        case .sshKey(let publicKey):
            try container.encode("sshKey", forKey: .type)
            try container.encode(publicKey, forKey: .args)
        }
    }
}
