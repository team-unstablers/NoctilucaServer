//
//  FeatureProvider.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation

public protocol FeatureProvider: AnyObject {
    // Returns true if the feature is supported
    func supports(_ feature: SiriusFeature) -> Bool

    func createChannel(
        for feature: SiriusFeature,
        using streamHolder: StreamHolder,
        identifier: ChannelIdentifier,
        direction: ChannelDirection,
        args: [String]
    ) -> Channel
}
