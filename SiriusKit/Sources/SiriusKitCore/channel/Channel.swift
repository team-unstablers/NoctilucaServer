//
//  Channel.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation
internal import SwiftProtobuf

internal import Atomics

public protocol Channel: AnyObject, Sendable {
    var handle: ChannelHandle { get }
    
    init(handle: ChannelHandle)
}

public extension Channel {
    var feature: SiriusFeature {
        handle.feature
    }

    var identifier: ChannelIdentifier {
        handle.identifier
    }

    var direction: ChannelDirection {
        handle.direction
    }
}

