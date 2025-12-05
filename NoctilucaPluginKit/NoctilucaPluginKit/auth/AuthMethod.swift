//
//  AuthEntry.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

/// 인증 방법을 나타냅니다.
/// - 각 인증 방법은 고유한 문자열 식별자를 가집니다.
///
/// # 확장 방법
/// 자체 인증 매커니즘을 추가하려면 이 구조체를 확장하여 고유한 `AuthMethod` 값을 정의하십시오.
/// - 자체 확장된 인증 매커니즘의 식별자는 충돌을 피하기 위하여 reverse domain name 형식을 따르는 것이 좋습니다.
///   (e.g., `pl.unstabler.noctiluca-ext.auth.fingerprint`)
public struct AuthMethod: RawRepresentable, Equatable, Hashable, Sendable, Codable {
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.rawValue = try container.decode(String.self)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    
    /// UNIX PAM 기반의 username-password 인증.`
    public static let password = AuthMethod(rawValue: "password")
    
    /// SSH 키 기반 인증.
    public static let sshKey = AuthMethod(rawValue: "ssh-key")
}

