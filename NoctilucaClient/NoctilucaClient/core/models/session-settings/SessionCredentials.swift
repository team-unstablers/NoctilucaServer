//
//  SessionCredentials.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

struct ClientAuthEntry: Codable, Sendable, Hashable, Identifiable {
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
    static let simplePassword = ClientAuthMethod(rawValue: "app.noctiluca.server.auth.simple-password")
    static let sshKey = ClientAuthMethod(rawValue: "ssh-key")
}

enum ClientAuthPayload: Codable, Hashable, Sendable {
    case password(username: String, password: String)
    case simplePassword(password: String)
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
        case simplePassword
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
        case .simplePassword:
            let password = try container.decode(String.self, forKey: .password)
            self = .simplePassword(password: password)
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
        case .simplePassword(let password):
            try container.encode(PayloadType.simplePassword, forKey: .type)
            try container.encode(password, forKey: .password)
        case .sshKey(let publicKey, let privateKey):
            try container.encode(PayloadType.sshKey, forKey: .type)
            try container.encode(publicKey, forKey: .publicKey)
            try container.encode(privateKey, forKey: .privateKey)
        }
    }
}

extension ClientAuthMethod {
    var displayName: String {
        switch self {
        case .password:
            return String(localized: "auth.method.password", defaultValue: "사용자명-비밀번호 인증")
        case .simplePassword:
            return String(localized: "auth.method.simple_password", defaultValue: "간단 비밀번호 인증")
        case .sshKey:
            return String(localized: "auth.method.ssh_key", defaultValue: "SSH 키 인증")
        default:
            return String(format: String(localized: "auth.method.external", defaultValue: "외부 인증 방법 (%@)"), rawValue)
        }
    }

    /// UI 표시 시 정렬 우선순위 (낮을수록 먼저 표시)
    var sortPriority: Int {
        switch self {
        case .password:
            return 0
        case .simplePassword:
            return 1
        case .sshKey:
            return 2
        default:
            return 100
        }
    }
}
