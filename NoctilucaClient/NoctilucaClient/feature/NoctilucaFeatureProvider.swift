//
//  NoctilucaFeatureProvider.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import SiriusKitClient

class NoctilucaFeatureProvider: FeatureProvider {
    func supports(_ feature: SiriusKitClient.SiriusFeature) -> Bool {
        switch feature {
        case .hidio:
            return true
        case .projection:
            return true
        case .projectionData:
            return true
            
        default:
            return false
        }
    }
    
    func createChannel(for feature: SiriusFeature,
                       using streamHolder: StreamHolder,
                       identifier: ChannelIdentifier,
                       direction: ChannelDirection,
                       args: [String]) -> Channel {
        
        switch feature {
        case .hidio:
            return HIDIOChannel(using: streamHolder, identifier: identifier, direction: direction)
        case .projection:
            return ProjectionChannel(using: streamHolder, identifier: identifier, direction: direction)
        case .projectionData:
            return ProjectionDataChannel(using: streamHolder, identifier: identifier, direction: direction)
        default:
            fatalError("Unsupported feature: \(feature)")
        }
    }
    
}
