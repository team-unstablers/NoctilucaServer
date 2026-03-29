//
//  MockFeatureProvider.swift
//  MockServer
//
//  Created by Gyuhwan Park on 2/13/26.
//

import Foundation
import SiriusKit

class MockFeatureProvider: FeatureProvider {
    let projectionSource: URL

    init(projectionSource: URL) {
        self.projectionSource = projectionSource
    }

    func supports(_ feature: SiriusFeature) -> Bool {
        switch feature {
        case .hidio, .projection, .projectionData:
            return true
        default:
            return false
        }
    }
    
    func createChannel(
        for feature: SiriusKitCore.SiriusFeature,
        using streamHolder: SiriusKitCore.StreamHolder,
        identifier: SiriusKitCore.ChannelIdentifier,
        direction: SiriusKitCore.ChannelDirection,
        args: [String]
    ) async throws -> SiriusKitCore.ChannelCreationResult {
        switch feature {
        case .hidio:
            return .accepted(MockHIDIOChannel(using: streamHolder, identifier: identifier, direction: direction))
        case .projection:
            return .accepted(MockProjectionChannel(
                using: streamHolder,
                identifier: identifier,
                direction: direction,
                projectionSource: projectionSource
            ))
        case .projectionData:
            return .accepted(ProjectionDataChannel(using: streamHolder, identifier: identifier, direction: direction))
        default:
            fatalError("Unsupported feature: \(feature)")
        }
    }
}
