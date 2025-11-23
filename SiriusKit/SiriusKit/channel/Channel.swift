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
    func channelDidClose(_ channel: Channel, error: (any Error)?)
}

enum ChannelError: Error {
    case invalidFrame
}

public class Channel: ChannelLike {
    public protocol HasFeature {
        var feature: SiriusFeature { get }
    }
    
    let stream: Stream
    
    public let identifier: ChannelIdentifier
    public let direction: ChannelDirection
    
    internal weak var lifecycleDelegate: ChannelLifecycleDelegate?

    required init(stream: Stream, identifier: ChannelIdentifier, direction: ChannelDirection) {
        self.stream = stream
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
    
    func handleFrame(frame: SiriusFrame) async throws {
        // to be overridden by subclasses
    }
    
    func handleStreamClose() {
        // default implementation
        
    }
    
    func handleStreamError(error: (any Error)) {
        // to be overridden by subclasses
    }
}

public extension Channel {
    convenience init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        self.init(stream: streamHolder.stream, identifier: identifier, direction: direction)
    }
}
