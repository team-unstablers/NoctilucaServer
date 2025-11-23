//
//  NoctilucaFeatureProvider.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import SiriusKit

class NoctilucaFeatureProvider: FeatureProvider {
    func supports(_ feature: SiriusKit.SiriusFeature) -> Bool {
    }
    
    func createChannel(for feature: SiriusKit.SiriusFeature,
                       using streamHolder: SiriusKit.StreamHolder,
                       identifier: SiriusKit.ChannelIdentifier,
                       direction: SiriusKit.ChannelDirection,
                       args: [String]) -> SiriusKit.Channel {
        
        switch feature {
        case .hidio:
            return HIDIOChannel(using: streamHolder, identifier: identifier, direction: direction)
        default:
            fatalError("Unsupported feature: \(feature)")
        }
    }
    
}
