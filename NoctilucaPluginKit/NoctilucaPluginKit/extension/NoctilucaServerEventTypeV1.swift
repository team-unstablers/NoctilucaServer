//
//  NoctilucaServerEventV1.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 5/17/26.
//

public struct NoctilucaServerEventTypeV1: RawRepresentable, Sendable, Hashable, Equatable {
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

public extension NoctilucaServerEventTypeV1 {
    static let authChallenge = Self(rawValue: "app.noctiluca.server.events.auth.challenge")
    static let authResult = Self(rawValue: "app.noctiluca.server.events.auth.result")
}

