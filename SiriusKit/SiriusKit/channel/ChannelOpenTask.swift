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
        
        stream.delegate = self
    }
    
    func blockUntilReceiveData() async throws -> (MessageOpcode, Data) {
        
    }
}

internal class RemoteChannelOpenTask: ChannelOpenTask {
    func perform(_ channelCreationBlock: ((ChannelStartRequest) async throws -> Bool)) async throws {
        let (opcode, data) = try await self.blockUntilReceiveData()
        // FIXME: EPILOGUE: 최대한 빨리 stream의 delegate / event subscription을 해제해야 한다

        guard opcode == .channelStartRequest,
              let request = try? ChannelStartRequest.fromProtobufBytes(data)
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
        let (opcode, data) = try await self.blockUntilReceiveData()
        // FIXME: EPILOGUE: 최대한 빨리 stream의 delegate / event subscription을 해제해야 한다

        guard opcode == .channelStartResponse,
              let response = try? ChannelStartResponse.fromProtobufBytes(data)
        else {
            throw ChannelManagerError.channelOpenFailed
        }
        
        guard response.success else {
            throw ChannelManagerError.channelOpenFailed
        }
    }
}


