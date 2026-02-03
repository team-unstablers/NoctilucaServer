//
//  TransportLayerImplType.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/17/25.
//

import Foundation

public enum TransportLayerProtocol: Hashable, CustomStringConvertible {
    case quic
    case custom(name: String)
    
    public var description: String {
        switch self {
        case .quic:
            return "QUIC"
        case .custom(let name):
            return name
        }
    }
}

public struct TransportLayerImplementation: Hashable {
    public let `protocol`: TransportLayerProtocol
    public let identifier: String
    public let displayName: String
    
    public let isBundled: Bool
    
    init(`protocol`: TransportLayerProtocol, identifier: String, displayName: String, isBundled: Bool) {
        self.protocol = `protocol`
        self.identifier = identifier
        self.displayName = displayName
        self.isBundled = isBundled
    }
    
    public init(`protocol`: TransportLayerProtocol, identifier: String, displayName: String) {
        self.init(protocol: `protocol`, identifier: identifier, displayName: displayName, isBundled: false)
    }
}

public extension TransportLayerImplementation {
    /// QUIC (Apple Network.framework)
    static let appleQuic = Self(
        protocol: .quic,
        identifier: "apple_quic",
        displayName: "QUIC (Network.framework)",
        isBundled: true
    )
    
    /// QUIC (Microsoft MsQuic)
    static let msQuic = Self(
        protocol: .quic,
        identifier: "msquic",
        displayName: "QUIC (MsQuic)",
        isBundled: true
    )
    
    static var bundledImplementations: [TransportLayerImplementation] {
        return [.appleQuic, .msQuic]
    }
}
