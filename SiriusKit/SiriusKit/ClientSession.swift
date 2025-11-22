//
//  ClientConnection.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation

public class ClientSession {
    let transport: ClientTransport
    
    private(set) public var mainChannel: MainChannel?
    public let channelManager: ChannelManager
    
    init(transport: ClientTransport) {
        self.transport = transport
        self.transport.delegate = self
        
        self.channelManager = ChannelManager()
    }
    
    // TODO: FeatureManager 등으로 옮겨야 하지 않을까?
    func openChannel<Ch>(for feature: SiriusFeature, identifier: UUID, args: [String] = []) async throws -> Ch where Ch: Channel {
        let result = await self.transport.openStream()
        
        switch result {
        case .failure(let error):
            throw error
        case .success(let stream):
            let channel = Ch(stream: stream)
            let request = ChannelStartRequest(
                featureID: feature.rawValue,
                channelID: identifier,
                args: args
            )
            
            try await channel.send(opcode: .channelStartRequest, message: request)
            let (opcode, data) = try await channel.blockUntilReceiveData()
            
            guard opcode == .channelStartResponse,
                  let response = try? ChannelStartResponse.fromProtobufBytes(data)
            else {
                throw ...
            }
            
            guard response.success else {
                throw ...
            }
            
            try channelManager.registerChannel(channel, for: identifier)
            // FIXME: channel identifier를 자기 자신이 가지고 있어야 함
            // FIXME: channel lifecycle를 감시하고, unregister를 할 수 있어야 함
            
            return channel
        }
    }
}

extension ClientSession: ClientTransportDelegate {
    func clientTransportDidOpenStream(_ transport: ClientTransport, stream: Stream) {
        if mainChannel == nil {
            // 첫번째 스트림은 반드시 메인 채널로 사용한다
            let channel = MainChannel(stream: stream)
            self.mainChannel = channel
            
            return
        }
        
        // 그럼 나머지는?
        // FIXME: 네이밍 컨벤션
        let tmpChannel: Channel = TmpChannel(stream: stream)
        let (opcode, data) = tmpChannel.blockUntilReceiveData()
        
        guard opcode == .channelStartRequest,
              let request = try? ChannelStartRequest.fromProtobufBytes(data)
        else {
            ...
            return
        }
        
        guard featureManager.supportsFeature(request.featureId) else {
            let response = ChannelStartResponse(success: false)
            
            try await tmpChannel.send(opcode: .channelStartResponse, message: response)
            return
        }
        
        let channel: Channel = try await featureManager.createChannel(request.featureID, direction: ..., args: ...)
        try channelManager.registerChannel(channel, for: request.channelID!)
    }
    
    func clientTransportDidCloseStream(_ transport: ClientTransport, stream: Stream) {
        //
    }
    
    func clientTransportDidClose(_ transport: ClientTransport, error: (any Error)?) {
    }
}
