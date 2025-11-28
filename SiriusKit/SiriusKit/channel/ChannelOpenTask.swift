//
//  ChannelOpenHelper.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import SwiftProtobuf

internal class ChannelOpenTask {
    var logger: SiriusLogger?
    
    let stream: Stream
    
    init(stream: Stream) {
        self.stream = stream
    }
    
    func send(opcode: MessageOpcode, message: (any SiriusMessage)) async throws {
        let protobufMessage = message.toProtobufMessage()
        let messageData = try protobufMessage.serializedData()
        
        self.logger?.trace("frame SEND - opcode \(opcode.hexString), length \(messageData.count)")

        let result = await self.stream.write(frame: messageData, opcode: opcode)
        
        if case .failure(let error) = result {
            throw error
        }
    }

    func blockUntilReceiveData() async throws -> SiriusFrame {
        self.logger?.warning("FIXME: blockUntilReceiveData() should have timeout parameter")
        
        for await event in stream.events {
            switch (event) {
            case .frame(let frame):
                self.logger?.trace("frame RECV - opcode \(frame.opcode.hexString), length \(frame.length)")
                return frame
            case .error(let error):
                self.logger?.error("caught error while waiting for data: \(error)")
                throw ChannelManagerError.channelOpenFailed
            case .closed:
                self.logger?.error("stream closed while waiting for data")
                throw ChannelManagerError.channelOpenFailed
            }
        }
        
        throw ChannelManagerError.channelOpenFailed
    }
}

internal class RemoteChannelOpenTask: ChannelOpenTask {
    
    override init(stream: Stream) {
        super.init(stream: stream)
        
        self.logger = SiriusLogger(category: "RemoteChannelOpenTask")
    }
    
    func perform(_ channelCreationBlock: ((ChannelStartRequest) async throws -> Bool)) async throws {
        self.logger?.info("performing remote channel open task - waiting for channel start request")
        
        let frame = try await self.blockUntilReceiveData()
        
        guard frame.isValid(),
              frame.opcode == .channelStartRequest,
              let request = try? ChannelStartRequest.fromProtobufBytes(frame.data)
        else {
            throw ChannelManagerError.channelOpenFailed
        }
        
        do {
            let isSuccess = try await channelCreationBlock(request)
            
            let response = ChannelStartResponse(success: isSuccess)
            try await self.send(opcode: .channelStartResponse, message: response)
        } catch {
            // FIXME: error handling
            let response = ChannelStartResponse(success: false)
            try await self.send(opcode: .channelStartResponse, message: response)
        }
        
    }
}

internal class LocalChannelOpenTask: ChannelOpenTask {
    let feature: SiriusFeature
    let identifier: ChannelIdentifier
    let args: [String]
    
    init(for feature: SiriusFeature,
         using stream: Stream,
         identifier: ChannelIdentifier,
         args: [String])
    {
        self.feature = feature
        self.identifier = identifier
        self.args = args
        
        super.init(stream: stream)
        
        self.logger = SiriusLogger(category: "LocalChannelOpenTask")
    }
    
    func perform() async throws {
        self.logger?.info("performing local channel open task - feature \(self.feature.rawValue), channel \(self.identifier)")
        
        let request = ChannelStartRequest(
            featureID: feature.rawValue,
            channelID: identifier,
            args: args
        )
        
        try await self.send(opcode: .channelStartRequest, message: request)
        
        let frame = try await self.blockUntilReceiveData()

        guard frame.isValid(),
              frame.opcode == .channelStartResponse,
              let response = try? ChannelStartResponse.fromProtobufBytes(frame.data)
        else {
            throw ChannelManagerError.channelOpenFailed
        }
        
        guard response.success else {
            throw ChannelManagerError.channelOpenFailed
        }
    }
}


