//
//  ChannelOpenHelper.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import SwiftProtobuf

internal class ChannelOpenTask: ChannelLike {
    let stream: Stream
    
    init(stream: Stream) {
        self.stream = stream
    }
    
    func blockUntilReceiveData() async throws -> SiriusFrame {
        for await event in stream.events {
            switch (event) {
            case .data(let data):
                guard let frame = data.toSiriusFrame() else {
                    throw ChannelManagerError.channelOpenFailed
                }
                
                return frame
                
            case .error(let error):
                // FIXME: error handling
                fallthrough
            case .closed:
                fallthrough
            default:
                throw ChannelManagerError.channelOpenFailed
            }
        }
        
        throw ChannelManagerError.channelOpenFailed
    }
}

internal class RemoteChannelOpenTask: ChannelOpenTask {
    func perform(_ channelCreationBlock: ((ChannelStartRequest) async throws -> Bool)) async throws {
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
    }
    
    func perform() async throws {
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


