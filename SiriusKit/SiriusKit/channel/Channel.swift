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
        self.stream.delegate = self
        
        self.identifier = identifier
    }
    
    public func close() async throws {
        try await self.stream.close()
    }
    
    func handleData(opcode: MessageOpcode, data: Data) {
        // to be overridden by subclasses
    }
    
    func handleStreamClose(error: (any Error)?) {
        self.lifecycleDelegate?.channelDidClose(self, error: error)
    }
}

extension Channel: StreamDelegate {
    func streamDidReceiveData(_ stream: Stream, data: Data) {
        self.handleData(opcode: .init(rawValue: 0x00), data: data) // FIXME
    }
    
    func streamDidClose(_ stream: Stream, error: (any Error)?) {
        self.handleStreamClose(error: error)
    }
}

internal extension Channel {
    // helper method
    func blockUntilReceiveData() async throws -> (MessageOpcode, Data) {
        // FIXME: implement me
    }
}

public extension Channel {
    convenience init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        self.init(stream: streamHolder.stream, identifier: identifier, direction: direction)
    }
}
