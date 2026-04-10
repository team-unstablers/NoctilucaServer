//
//  MockFeatureProvider.swift
//  SiriusKitClientTests
//

import Foundation
@testable import SiriusKitCore

final class MockFeatureProvider: FeatureProvider, @unchecked Sendable {
    var supportedFeatures: Set<SiriusFeature> = [.hidio, .projection, .projectionData]

    private(set) var createdChannels: [(feature: SiriusFeature, identifier: ChannelIdentifier)] = []

    func supports(_ feature: SiriusFeature) -> Bool {
        supportedFeatures.contains(feature)
    }

    func createChannel(
        for feature: SiriusFeature,
        handle: ChannelHandle,
        args: [String]
    ) async throws -> ChannelCreationResult {
        createdChannels.append((feature: feature, identifier: handle.identifier))
        return .accepted(MockChannel(handle: handle))
    }
}
