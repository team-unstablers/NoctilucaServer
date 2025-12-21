//
//  SessionCredentials.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

struct ClientAuthEntry: Codable, Sendable, Hashable {
    var id: UUID = UUID()
    var method: ClientAuthMethod
    var displayName: String? = nil
    var payload: ClientAuthPayload
}

struct ClientAuthMethod: RawRepresentable, Equatable, Hashable, Sendable, Codable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let password = ClientAuthMethod(rawValue: "password")
    static let sshKey = ClientAuthMethod(rawValue: "ssh-key")
}

enum ClientAuthPayload: Codable, Hashable, Sendable {
    case password(username: String, password: String)
    case sshKey(publicKey: String, privateKey: Data)

    private enum CodingKeys: String, CodingKey {
        case type
        case username
        case password
        case publicKey
        case privateKey
    }

    private enum PayloadType: String, Codable {
        case password
        case sshKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(PayloadType.self, forKey: .type)
        switch type {
        case .password:
            let username = try container.decode(String.self, forKey: .username)
            let password = try container.decode(String.self, forKey: .password)
            self = .password(username: username, password: password)
        case .sshKey:
            let publicKey = try container.decode(String.self, forKey: .publicKey)
            let privateKey = try container.decode(Data.self, forKey: .privateKey)
            self = .sshKey(publicKey: publicKey, privateKey: privateKey)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .password(let username, let password):
            try container.encode(PayloadType.password, forKey: .type)
            try container.encode(username, forKey: .username)
            try container.encode(password, forKey: .password)
        case .sshKey(let publicKey, let privateKey):
            try container.encode(PayloadType.sshKey, forKey: .type)
            try container.encode(publicKey, forKey: .publicKey)
            try container.encode(privateKey, forKey: .privateKey)
        }
    }
}
