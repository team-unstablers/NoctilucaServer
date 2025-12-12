//
//  ChannelManager.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation

enum ChannelManagerError: Error {
    case channelOpenFailed
    case channelAlreadyRegistered
}

public class ChannelManager {
    internal let session: (any SiriusSession)
    
    private(set) public var mainChannel: MainChannel?
    private(set) public var channels: [UUID: Channel] = [:]
    
    init(session: (any SiriusSession)) {
        self.session = session
    }
    
    func registerChannel(_ channel: Channel) throws {
        guard !channels.keys.contains(channel.identifier) else {
            throw ChannelManagerError.channelAlreadyRegistered
        }
        
        channel.lifecycleDelegate = self
        
        self.channels[channel.identifier] = channel
    }
    
    func unregisterChannel(identifier: UUID) {
        self.channels.removeValue(forKey: identifier)
    }
    
    public func filter(byFeature feature: SiriusFeature) -> [Channel] {
        return self.channels.values.filter {
            ($0 as? Channel.HasFeature)?.feature == feature
        }
    }
    
    /// Main Channel을 엽니다. (client role 전용)
    internal func clientOpenMainChannel() async throws {
        let result = await session.transport.openStream()
        
        switch result {
        case .failure(let error):
            throw error
        case .success(let stream):
            let mainChannel = MainChannel(stream: stream, identifier: ChannelIdentifier(), direction: .local)
            mainChannel.session = self.session
            self.mainChannel = mainChannel
            
            return
        }
    }
    
    public func openChannel(for feature: SiriusFeature, identifier: ChannelIdentifier, args: [String] = []) async throws -> Channel {
        guard session.featureProvider.supports(feature) else {
            // 이거 에러가 너무 제너릭하지 않아?
            fatalError("Feature \(feature) is not supported by the session's feature provider")
            throw ChannelManagerError.channelOpenFailed
        }
        
        let result = await session.transport.openStream()
        
        switch result {
        case .failure(let error):
            throw error
        case .success(let stream):
            let openTask = LocalChannelOpenTask(for: feature, using: stream, identifier: identifier, args: args)
            try await openTask.perform()
            
            let channel = session.featureProvider.createChannel(
                for: feature,
                using: StreamHolder(stream: stream),
                identifier: identifier,
                direction: .local,
                args: args
            )
            channel.session = self.session
            
            print("Opened channel \(channel.identifier) for feature \(feature)")

            try self.registerChannel(channel)
            
            print("Registered channel \(channel.identifier)")

            return channel
        }
    }
    
    internal func handleStreamOpen(stream: Stream) async throws {
        if mainChannel == nil {
            // 첫번째 스트림은 반드시 메인 채널로 사용한다
            // 프로토콜 상 약속이므로 ChannelOpenTask를 사용할 필요가 없다
            let channel = MainChannel(stream: stream, identifier: ChannelIdentifier(), direction: .local)
            channel.session = self.session
            
            self.mainChannel = channel
            return
        }
        
        guard session.shouldAcceptChannelCreation else {
            // 채널 생성을 허용하지 않음 (인증 전 등)
            try await stream.close()
            return
        }
        
        // 그럼 나머지는?
        let openTask = RemoteChannelOpenTask(stream: stream)
        try await openTask.perform { request in
            let feature = SiriusFeature(rawValue: request.featureID!)
            
            guard session.featureProvider.supports(feature) else {
                return false
            }
            
            let channel: Channel = session.featureProvider.createChannel(
                for: feature,
                using: StreamHolder(stream: stream),
                identifier: request.channelID!,
                direction: .remote,
                args: request.args
            )
            channel.session = self.session
                
            try self.registerChannel(channel)
            return true
        }
    }
    
}

extension ChannelManager: ChannelLifecycleDelegate {
    func channelDidClose(_ channel: Channel) {
        self.unregisterChannel(identifier: channel.identifier)
    }
    
    func channel(_ channel: Channel, didEncounterError error: any Error) {
        self.unregisterChannel(identifier: channel.identifier)
    }
}
