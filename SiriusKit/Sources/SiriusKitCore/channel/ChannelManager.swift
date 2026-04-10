//
//  ChannelManager.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation


fileprivate extension SiriusEventLogger.EventType {
    static let channelOpen  = Self(rawValue: "CHANNEL_OPEN")
    static let channelClose = Self(rawValue: "CHANNEL_CLOSE")
}

enum ChannelManagerError: Error {
    /// 채널 생성에 실패하였습니다.
    case channelOpenFailed
    /// 채널 생성을 거절하였습니다.
    case channelOpenRejected(code: Int, reason: String)
    case channelOpenTimedOut
    case channelAlreadyRegistered
}

public protocol ChannelManagerDelegate: AnyObject {
    func channelManager(_ manager: ChannelManager, didRegisterChannel channel: any Channel, for feature: SiriusFeature)
    func channelManager(_ manager: ChannelManager, willUnregisterChannel channel: any Channel)
}

public actor ChannelManager {
    private let logger = SiriusLogger(category: "ChannelManager")
    private var eventLogger: SiriusEventLogger?

    internal unowned let session: (any SiriusSession)
    private let channelOpenTimeout: TimeInterval

    private(set) public var mainChannel: MainChannel?
    private(set) public var channels: [UUID: any Channel] = [:]

    private weak var delegate: ChannelManagerDelegate?
    

    package init(session: (any SiriusSession), channelOpenTimeout: TimeInterval = 5) {
        self.session = session
        self.channelOpenTimeout = channelOpenTimeout
    }
    
    package func createEventLogger(_ context: SharedState<SiriusEventLogger.Context>) {
        self.eventLogger = SiriusEventLogger("SiriusKit::ChannelManager", context: context)
    }

    public func setDelegate(_ delegate: ChannelManagerDelegate?) {
        self.delegate = delegate
    }

    func registerChannel(_ channel: Channel, for feature: SiriusFeature) throws {
        guard !channels.keys.contains(channel.identifier) else {
            throw ChannelManagerError.channelAlreadyRegistered
        }

        defer {
            delegate?.channelManager(self, didRegisterChannel: channel, for: feature)
        }

        channel.handle.asImpl.lifecycleDelegate = self

        self.channels[channel.identifier] = channel
    }

    func unregisterChannel(identifier: UUID) {
        if self.mainChannel?.identifier == identifier {
            self.mainChannel = nil
            return
        }

        if let channel = self.channels[identifier] {
            delegate?.channelManager(self, willUnregisterChannel: channel)
        }

        self.channels.removeValue(forKey: identifier)
    }

    public func filter(byFeature feature: SiriusFeature) -> [Channel] {
        return self.channels.values.filter {
            $0.feature == feature
        }
    }

    /// Main Channel을 엽니다. (client role 전용)
    package func clientOpenMainChannel() async throws {
        let result = await session.transport.openStream()

        switch result {
        case .failure(let error):
            throw error
        case .success(let stream):
            let handle = ChannelHandleImpl(
                feature: .init(rawValue: .zero),
                session: session,
                stream: stream,
                identifier: ChannelIdentifier(),
                direction: .local
            )
            
            let mainChannel = MainChannel(handle: handle)
            handle.lifecycleDelegate = self
            
            try await handle.activate()
            
            self.mainChannel = mainChannel

            return
        }
    }

    public func openChannel(for feature: SiriusFeature, identifier: ChannelIdentifier, args: [String] = []) async throws -> Channel {
        var success = false
        defer {
            self.eventLogger?.log(.channelOpen, args: [
                "direction": "LOCAL",
                "channel_id": identifier.uuidString,
                "feature_id": feature.rawValue.uuidString,
                "success": success.description,
            ])
        }
        
        guard session.featureProvider.supports(feature) else {
            // 이거 에러가 너무 제너릭하지 않아?
            logger.error("Feature \(feature) is not supported by the session's feature provider")
            throw ChannelManagerError.channelOpenFailed
        }

        let result = await session.transport.openStream()

        switch result {
        case .failure(let error):
            throw error
        case .success(let stream):
            defer {
                if !success {
                    // 채널 열기에 실패했으니 스트림을 닫는다
                    Task.detached { [stream] in
                        try? await stream.close()
                    }
                }
            }
            
            let openTask = LocalChannelOpenTask(
                for: feature,
                using: stream,
                identifier: identifier,
                args: args,
                timeout: channelOpenTimeout
            )
            try await openTask.perform()
            
            let handle = ChannelHandleImpl(
                feature: feature,
                session: session,
                stream: stream,
                identifier: identifier,
                direction: .local
            )
            
            let result = try await session.featureProvider.createChannel(
                for: feature,
                handle: handle,
                args: args
            )
            
            guard case .accepted = result else {
                // 왜 `assert(case .accepted = result)` 이런거 안됨 ㅡㅡ
                assert(false, "Feature provider's createChannel must return .accepted if openTask.perform() succeeds")
                throw ChannelManagerError.channelOpenFailed
            }
            
            switch result {
            case .accepted(let channel):
                success = true

                logger.info("Opened channel \(channel.identifier) for feature \(feature)")
                try self.registerChannel(channel, for: feature)
                logger.info("Registered channel \(channel.identifier)")

                try await handle.activate()

                return channel
            case .rejected(let code, let reason):
                logger.warning("channel creation rejected (direction = local, feature = \(feature.rawValue))")
                throw ChannelManagerError.channelOpenRejected(code: code, reason: reason)
            }
        }
    }

    package func handleStreamOpen(stream: Stream) async throws {
        if mainChannel == nil {
            // 첫번째 스트림은 반드시 메인 채널로 사용한다
            // 프로토콜 상 약속이므로 ChannelOpenTask를 사용할 필요가 없다
            let handle = ChannelHandleImpl(
                feature: .init(rawValue: .zero),
                session: session,
                stream: stream,
                identifier: ChannelIdentifier(),
                direction: .local
            )
            
            let mainChannel = MainChannel(handle: handle)
            handle.lifecycleDelegate = self
            
            try await handle.activate()

            self.mainChannel = mainChannel
            return
        }

        guard session.shouldAcceptChannelCreation else {
            // 채널 생성을 허용하지 않음 (인증 전 등)
            try await stream.close()
            return
        }

        // 그럼 나머지는?
        let openTask = RemoteChannelOpenTask(stream: stream, timeout: channelOpenTimeout)
        var success = false
        var createdChannel: Channel?

        defer {
            if !success {
                // 채널 열기에 실패했으니 스트림을 닫는다
                Task.detached { [stream] in
                    try? await stream.close()
                }
            }
        }

        try await openTask.perform { request in
            guard let featureID = request.featureID,
                  let channelID = request.channelID else {
                self.logger.warning("Received channel open request with missing featureID or channelID")
                return false
            }

            let feature = SiriusFeature(rawValue: featureID)

            defer {
                self.eventLogger?.log(.channelOpen, args: [
                    "direction": "REMOTE",
                    "channel_id": channelID.uuidString,
                    "feature_id": featureID.uuidString,
                    "success": success.description,
                ])
            }

            guard session.featureProvider.supports(feature) else {
                return false
            }
            
            let handle = ChannelHandleImpl(
                feature: feature,
                session: session,
                stream: stream,
                identifier: channelID,
                direction: .remote
            )

            let result = try await session.featureProvider.createChannel(
                for: feature,
                handle: handle,
                args: request.args
            )

            switch result {
            case .accepted(let channel):
                try self.registerChannel(channel, for: feature)
                
                success = true
                createdChannel = channel

                return true

            case .rejected(let code, let reason):
                logger.warning("channel creation rejected (direction = remote, feature = \(feature.rawValue))")
                throw ChannelManagerError.channelOpenRejected(code: code, reason: reason)
            }
        }
        
        try await createdChannel?.handle?.activate()
    }

    package func teardownAllChannels() async {
        let mainChannel = self.mainChannel
        let channels = Array(self.channels.values)

        self.mainChannel = nil
        self.channels.removeAll()

        for channel in channels {
            delegate?.channelManager(self, willUnregisterChannel: channel)
            channel.handle.asImpl.lifecycleDelegate = nil
        }
        mainChannel?.handle.asImpl.lifecycleDelegate = nil

        for channel in channels {
            do {
                try await channel.handle.close()
            } catch {
                logger.warning("Failed to close channel \(channel.identifier) during teardown: \(error)")
            }
        }

        guard let mainChannel else {
            return
        }

        do {
            try await mainChannel.handle.close()
        } catch {
            logger.warning("Failed to close main channel \(mainChannel.identifier) during teardown: \(error)")
        }
    }

}

extension ChannelManager: ChannelLifecycleDelegate {
    nonisolated func channelDidClose(_ handle: any ChannelHandle) {
        Task { await self.unregisterChannel(identifier: handle.identifier) }
    }

    nonisolated func channel(_ handle: any ChannelHandle, didEncounterError error: any Error) {
        Task { await self.unregisterChannel(identifier: handle.identifier) }
    }
}
