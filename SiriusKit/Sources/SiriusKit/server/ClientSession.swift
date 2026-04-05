//
//  ClientConnection.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation
internal import Atomics
import SiriusKitCore

public protocol ClientSessionDelegate: AnyObject {
    func clientSessionDidCloseTransport(_ session: ClientSession)
    func clientSessionDidCreateMainChannel(_ session: ClientSession, mainChannel: MainChannel)
}

protocol ClientSessionLifecycleDelegate: AnyObject {
    func clientSessionDidClose(_ session: ClientSession)
}

public class ClientSession: SiriusSession, @unchecked Sendable {
    private let logger = SiriusLogger(category: "ClientSession")

    public let id: UUID

    let clientTransport: any ServerRoleClientTransport
    package var transport: any TransportLayer { clientTransport }

    public var remoteEndpoint: SREndpoint? {
        clientTransport.remoteEndpoint
    }

    package let featureProvider: (any FeatureProvider)

    public var channelManager: ChannelManager!
    public var shouldAcceptChannelCreation: Bool = false

    public weak var delegate: (any ClientSessionDelegate)?
    weak var lifecycleDelegate: (any ClientSessionLifecycleDelegate)?
    
    private(set) public var eventLoggerContext: SharedState<SiriusEventLogger.Context>
    private let eventLogger: SiriusEventLogger
    private let isActivated = ManagedAtomic(false)
    private let didNotifyTransportClosure = ManagedAtomic(false)

    init(id: UUID, transport: any ServerRoleClientTransport, featureProvider: (any FeatureProvider), eventLoggerContext: SharedState<SiriusEventLogger.Context>) {
        self.id = id

        self.clientTransport = transport
        self.featureProvider = featureProvider
        
        self.eventLoggerContext = eventLoggerContext
        self.eventLogger = SiriusEventLogger("SiriusKit::ClientSession", context: eventLoggerContext)
        
        self.channelManager = ChannelManager(session: self)
    }

    func activate() {
        guard isActivated.compareExchange(expected: false, desired: true, ordering: .acquiring).original == false else {
            return
        }

        self.clientTransport.delegate = self

        Task {
            await self.channelManager.createEventLogger(self.eventLoggerContext)
            await self.initialize()
        }
    }
    
    /// transport delegate 설정 전에 열린 스트림이 있으면 메인 채널로 승격시키고, delegate를 설정합니다.
    private func initialize() async {
        guard await channelManager.mainChannel == nil else {
            return
        }

        let streams = await clientTransport.getStreams().values

        guard await channelManager.mainChannel == nil else {
            return
        }

        guard let mainChannelStream = streams.first else {
            return
        }

        if streams.count > 1 {
            logger.error("Multiple streams were opened before delegate was set, which is unexpected. Count: \(streams.count)")
        }

        logger.info("Found \(streams.count) pre-opened stream(s). Promoting the first one to main channel.")

        try? await channelManager.handleStreamOpen(stream: mainChannelStream)
        guard let mainChannel = await channelManager.mainChannel else {
            logger.error("Main channel was not created after stream open.")
            return
        }
        self.delegate?.clientSessionDidCreateMainChannel(self, mainChannel: mainChannel)
    }

    public func close() async {
        shouldAcceptChannelCreation = false
        await channelManager.teardownAllChannels()
        await self.clientTransport.disconnect()
        notifyTransportClosedIfNeeded()
    }
    
    /// 트랜스포트 레이어 레벨의 세션 재개 티켓을 클라이언트에게 발행합니다.
    /// Note: 트랜스포트 레이어 구현체에 따라 이 동작은 No-op일 수도 있습니다.
    ///
    /// 만일을 대비하여, 메인 페이즈에 진입한 후에 이 메서드를 호출하는 것을 권장합니다.
    public func issueResumeTicket() async {
        do {
            try await clientTransport.issueResumeTicket()
        } catch {
            logger.error("Failed to issue resume ticket: \(error)")
        }
    }

    private func notifyTransportClosedIfNeeded() {
        guard didNotifyTransportClosure.compareExchange(expected: false, desired: true, ordering: .acquiring).original == false else {
            return
        }

        lifecycleDelegate?.clientSessionDidClose(self)
        delegate?.clientSessionDidCloseTransport(self)
    }
}

extension ClientSession: ServerRoleClientTransportDelegate {
    func clientTransportDidOpenRemoteStream(_ transport: any ServerRoleClientTransport, stream: SiriusKitCore.Stream) async throws {
        logger.info("ClientSession \(self.id) received remote stream open.")

        if await channelManager.mainChannel == nil {
            // 첫번째 스트림은 반드시 메인 채널로 사용한다
            try await channelManager.handleStreamOpen(stream: stream)
            guard let mainChannel = await channelManager.mainChannel else {
                logger.error("Main channel was not created after stream open.")
                return
            }
            self.delegate?.clientSessionDidCreateMainChannel(self, mainChannel: mainChannel)

            return
        }

        try await channelManager.handleStreamOpen(stream: stream)
    }

    func clientTransportDidCloseStream(_ transport: any ServerRoleClientTransport, stream: SiriusKitCore.Stream) async {
        //
    }

    func clientTransportDidClose(_ transport: any ServerRoleClientTransport) async {
        shouldAcceptChannelCreation = false
        await channelManager.teardownAllChannels()
        notifyTransportClosedIfNeeded()
    }

    func clientTransport(_ transport: any ServerRoleClientTransport, didEncounterError error: any Error) async {
    }
}
