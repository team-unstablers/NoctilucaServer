//
//  SiriusProtocol.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation

public struct SiriusProtocolVersion: RawRepresentable, Equatable, Hashable {
    public typealias RawValue = UInt32
    public let rawValue: RawValue
    
    public init(rawValue: RawValue) {
        self.rawValue = rawValue
    }
    
    public static let v1_0: SiriusProtocolVersion = SiriusProtocolVersion(rawValue: 1)
}


public struct SiriusFeature: RawRepresentable, Equatable, Hashable {
    public typealias RawValue = UUID
    public let rawValue: UUID
    
    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }
    
}
