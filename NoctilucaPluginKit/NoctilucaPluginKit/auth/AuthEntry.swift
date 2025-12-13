//
//  AuthEntry.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 12/5/25.
//

import Foundation

@frozen
public struct AuthEntry: Sendable, Hashable {
    public let method: AuthMethod
    
    /// 사용자 식별자
    public let identifier: String
    /// 인증에 필요한 추가 데이터
    public let data: Data?
    
    public init(method: AuthMethod, identifier: String, data: Data? = nil) {
        self.method = method
        self.identifier = identifier
        self.data = data
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(method)
        hasher.combine(identifier)
        hasher.combine(data)
    }
}
