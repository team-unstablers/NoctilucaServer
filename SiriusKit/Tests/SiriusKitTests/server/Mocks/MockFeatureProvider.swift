//
//  MockFeatureProvider.swift
//  SiriusKitTests
//

import Foundation
@testable import SiriusKitCore

final class MockFeatureProvider: FeatureProvider {
    var supportedFeatures: Set<SiriusFeature> = [.hidio, .projection, .projectionData]

    private(set) var createdChannels: [(feature: SiriusFeature, identifier: ChannelIdentifier)] = []

    func supports(_ feature: SiriusFeature) -> Bool {
        supportedFeatures.contains(feature)
    }

    func createChannel(
        for feature: SiriusFeature,
        using streamHolder: StreamHolder,
        identifier: ChannelIdentifier,
        direction: ChannelDirection,
        args: [String]
    ) -> Channel {
        createdChannels.append((feature: feature, identifier: identifier))
        return Channel(using: streamHolder, identifier: identifier, direction: direction)
    }
}
