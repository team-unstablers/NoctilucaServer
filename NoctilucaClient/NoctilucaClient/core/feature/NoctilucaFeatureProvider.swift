//
//  NoctilucaFeatureProvider.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import SiriusKitClient

class NoctilucaFeatureProvider: FeatureProvider {
    func supportedFeatures() -> [SiriusFeature] {
        return [
            .hidio,
            .projection,
            .transfer,
            .clipboard,
        ]
    }
    
    func supports(_ feature: SiriusKitClient.SiriusFeature) -> Bool {
        switch feature {
        case .hidio:
            return true
        case .projection:
            return true
        case .projectionData:
            return true
            
        case .transfer:
            return true

        case .clipboard:
            return true

        default:
            return false
        }
    }
    
    func createChannel(for feature: SiriusKitClient.SiriusFeature,
                       using streamHolder: SiriusKitClient.StreamHolder,
                       identifier: SiriusKitClient.ChannelIdentifier,
                       direction: SiriusKitClient.ChannelDirection,
                       args: [String]) async throws -> ChannelCreationResult {
        
        switch feature {
        case .hidio:
            return .accepted(HIDIOChannel(using: streamHolder, identifier: identifier, direction: direction))
        case .projection:
            return .accepted(ProjectionChannel(using: streamHolder, identifier: identifier, direction: direction))
        case .projectionData:
            return .accepted(ProjectionDataChannel(using: streamHolder, identifier: identifier, direction: direction))
            
        case .transfer:
            return try await TransferChannel.createIfAccepts(
                streamHolder,
                identifier: identifier,
                direction: direction,
                args: args
            )

        case .clipboard:
            return .accepted(ClipboardChannel(using: streamHolder, identifier: identifier, direction: direction))

        default:
            fatalError("Unsupported feature: \(feature)")
        }
    }
    
}
