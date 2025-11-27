//
//  Channel.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation
import SwiftProtobuf

public typealias ChannelIdentifier = UUID

public enum ChannelDirection {
    case local
    case remote
}

internal protocol ChannelLifecycleDelegate: AnyObject {
    func channelDidClose(_ channel: Channel)
    func channel(_ channel: Channel, didEncounterError error: any Error)
}

public enum ChannelError: Error {
    case invalidFrame
}

open class Channel: ChannelLike {
    public protocol HasFeature {
        var feature: SiriusFeature { get }
    }
    
    let stream: Stream
    
    public let identifier: ChannelIdentifier
    public let direction: ChannelDirection
    
    internal weak var lifecycleDelegate: ChannelLifecycleDelegate?

    required public init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        self.stream = streamHolder.stream
        self.identifier = identifier
        self.direction = direction
    }

    public func close() async throws {
        try await self.stream.close()
    }
    
    private func streamEventLoop() async throws {
        for await event in self.stream.events {
            switch event {
            case .frame(let frame):
                try await self.handleFrame(frame: frame)
            case .closed:
                self.handleStreamClose()
                return
            case .error(let error):
                self.handleStreamError(error: error)
                return
            }
            
        }
    }
    
    open func handleFrame(frame: SiriusFrame) async throws {
        // to be overridden by subclasses
    }
    
    open func handleStreamClose() {
        // default implementation
        
    }
    
    open func handleStreamError(error: (any Error)) {
        // to be overridden by subclasses
    }
}

extension Channel {
    convenience init(stream: Stream, identifier: ChannelIdentifier, direction: ChannelDirection) {
        self.init(using: StreamHolder(stream: stream), identifier: identifier, direction: direction)
    }
}
