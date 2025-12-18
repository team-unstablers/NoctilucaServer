//
//  TransportLayerImplType.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 12/17/25.
//

import Foundation

public enum TransportLayerImplementation: String, Hashable, Codable, CustomStringConvertible {
    case appleQUIC = "apple_quic"
    
    public var description: String {
        switch self {
        case .appleQUIC:
            return "QUIC (SiriusKit + Apple Network.framework)"
        }
    }
    
    public static var allCases: [TransportLayerImplementation] {
        return [.appleQUIC]
    }
}
