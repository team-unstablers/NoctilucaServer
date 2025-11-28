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

open class Channel {
    public protocol HasFeature {
        var feature: SiriusFeature { get }
    }
    
    private static let sharedLogger = SiriusLogger(category: "Channel")
    private var logger: SiriusLogger { Self.sharedLogger }
    
    let stream: Stream
    
    private var streamEventLoopTask: Task<Void, any Error>? = nil
    
    public let identifier: ChannelIdentifier
    public let direction: ChannelDirection
    
    internal weak var lifecycleDelegate: ChannelLifecycleDelegate?

    required public init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        self.stream = streamHolder.stream
        self.identifier = identifier
        self.direction = direction
        
        self.streamEventLoopTask = Task {
            do {
                try await self.streamEventLoop()
            } catch {
                self.logger.error("[\(self.identifier)] encountered error in stream event loop: \(error)")
                self.lifecycleDelegate?.channel(self, didEncounterError: error)
            }
        }
    }

    public func close() async throws {
        try await self.stream.close()
    }
    
    internal func send(opcode: MessageOpcode, message: (any SiriusMessage)) async throws {
        let protobufMessage = message.toProtobufMessage()
        let messageData = try protobufMessage.serializedData()
        
#if DEBUG
        self.logger.trace("[\(self.identifier)] frame SEND - opcode \(opcode.hexString), length \(messageData.count)")
#endif

        let result = await self.stream.write(frame: messageData, opcode: opcode)
        
        if case .failure(let error) = result {
            throw error
        }
    }

    private func streamEventLoop() async throws {
        for await event in self.stream.events {
            switch event {
            case .frame(let frame):
                // 아, 이거 매크로로 하면 개편할텐데 ㅠ
#if DEBUG
                self.logger.trace("[\(self.identifier)] frame RECV - opcode \(frame.opcode.hexString), length \(frame.length)")
#endif
                
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
