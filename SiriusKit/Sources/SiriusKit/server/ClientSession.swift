//
//  ClientConnection.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation
import SiriusKitCore

public protocol ClientSessionDelegate: AnyObject {
    func clientSessionDidCloseTransport(_ session: ClientSession)
    func clientSessionDidCreateMainChannel(_ session: ClientSession, mainChannel: MainChannel)
}

public class ClientSession: SiriusSession {
    private let logger = SiriusLogger(category: "ClientSession")

    public let id: UUID

    let clientTransport: any ServerRoleClientTransport
    package var transport: any TransportLayer { clientTransport }

    public var remoteAddress: String? {
        clientTransport.remoteAddress
    }

    package let featureProvider: (any FeatureProvider)

    public var channelManager: ChannelManager!
    public var shouldAcceptChannelCreation: Bool = false

    public weak var delegate: (any ClientSessionDelegate)?

    init(id: UUID, transport: any ServerRoleClientTransport, featureProvider: (any FeatureProvider)) {
        self.id = id

        self.clientTransport = transport
        self.featureProvider = featureProvider
        self.channelManager = ChannelManager(session: self)

        self.clientTransport.delegate = self
    }

    public func close() async {
        await self.clientTransport.disconnect()
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
        self.delegate?.clientSessionDidCloseTransport(self)
    }

    func clientTransport(_ transport: any ServerRoleClientTransport, didEncounterError error: any Error) async {
    }
}
