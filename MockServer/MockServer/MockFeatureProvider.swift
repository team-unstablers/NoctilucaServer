//
//  MockFeatureProvider.swift
//  MockServer
//
//  Created by Gyuhwan Park on 2/13/26.
//

import Foundation
import SiriusKit

final class MockFeatureProvider: FeatureProvider {
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
        handle: ChannelHandle,
        args: [String]
    ) async throws -> ChannelCreationResult {
        switch feature {
        case .hidio:
            return .accepted(MockHIDIOChannel(handle: handle))
        case .projection:
            return .accepted(MockProjectionChannel(handle: handle, projectionSource: projectionSource))
        case .projectionData:
            return .accepted(ProjectionDataChannel(handle: handle))
        default:
            fatalError("Unsupported feature: \(feature)")
        }
    }
}
