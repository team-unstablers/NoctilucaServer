//
//  NoctilucaPluginKit.swift
//  NoctilucaPluginKit
//
//  Created by Gyuhwan Park on 12/5/25.
//

public struct NoctilucaPluginKitVersion: RawRepresentable, Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let v1 = Self.init(rawValue: 0x0001_0000)
}
