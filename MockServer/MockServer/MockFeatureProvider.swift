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
        for feature: SiriusFeature,
        using streamHolder: StreamHolder,
        identifier: ChannelIdentifier,
        direction: ChannelDirection,
        args: [String]
    ) -> Channel {
        switch feature {
        case .hidio:
            return MockHIDIOChannel(using: streamHolder, identifier: identifier, direction: direction)
        case .projection:
            return MockProjectionChannel(
                using: streamHolder,
                identifier: identifier,
                direction: direction,
                projectionSource: projectionSource
            )
        case .projectionData:
            return ProjectionDataChannel(using: streamHolder, identifier: identifier, direction: direction)
        default:
            fatalError("Unsupported feature: \(feature)")
        }
    }
}
