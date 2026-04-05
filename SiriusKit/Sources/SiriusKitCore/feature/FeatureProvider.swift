//
//  FeatureProvider.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation

public enum ChannelCreationResult: Sendable {
    case accepted(Channel)
    case rejected(code: Int, reason: String)
}

public protocol FeatureProvider: AnyObject, Sendable {
    // Returns true if the feature is supported
    func supports(_ feature: SiriusFeature) -> Bool

    func createChannel(
        for feature: SiriusFeature,
        using streamHolder: StreamHolder,
        identifier: ChannelIdentifier,
        direction: ChannelDirection,
        args: [String]
    ) async throws -> ChannelCreationResult
}
