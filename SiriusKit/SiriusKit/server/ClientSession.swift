//
//  ClientConnection.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation

public protocol ClientSessionDelegate: AnyObject {
    func clientSessionDidCloseTransport(_ session: ClientSession)
    func clientSessionDidCreateMainChannel(_ session: ClientSession, mainChannel: MainChannel)
}

public class ClientSession: SiriusSession {
    private let logger = SiriusLogger(category: "ClientSession")
    
    public let id: UUID
    
    
    let clientTransport: any ServerRoleClientTransport
    var transport: any TransportLayer { clientTransport }
    
    public var remoteAddress: String? {
        clientTransport.remoteAddress
    }

    let featureProvider: (any FeatureProvider)
    
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
}

extension ClientSession: ServerRoleClientTransportDelegate {
    func clientTransportDidOpenRemoteStream(_ transport: any ServerRoleClientTransport, stream: Stream) async throws {
        logger.info("ClientSession \(self.id) received remote stream open.")
        
        if channelManager.mainChannel == nil {
            // 첫번째 스트림은 반드시 메인 채널로 사용한다
            try await channelManager.handleStreamOpen(stream: stream)
            self.delegate?.clientSessionDidCreateMainChannel(self, mainChannel: channelManager.mainChannel!)
            
            return
        }
        
        try await channelManager.handleStreamOpen(stream: stream)
    }
    
    func clientTransportDidCloseStream(_ transport: any ServerRoleClientTransport, stream: Stream) async {
        //
    }
    
    func clientTransportDidClose(_ transport: any ServerRoleClientTransport) async {
        self.delegate?.clientSessionDidCloseTransport(self)
    }
    
    func clientTransport(_ transport: any ServerRoleClientTransport, didEncounterError error: any Error) async {
    }
}
