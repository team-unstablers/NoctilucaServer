//
//  ClientConnection.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation

public protocol SiriusClientDelegate: AnyObject {
    func siriusClient(_ client: SiriusClient, didCreateMainChannel mainChannel: MainChannel)
    func siriusClientDidCloseTransport(_ client: SiriusClient)
}

public class SiriusClient: SiriusSession {
    private let logger = SiriusLogger(category: "SiriusClient")
    
    public let id: UUID
    
    let clientTransport: any ClientRoleTransport
    var transport: any TransportLayer { clientTransport }
    
    let featureProvider: (any FeatureProvider)
    
    public var channelManager: ChannelManager!
    public var shouldAcceptChannelCreation: Bool = false
    
    public weak var delegate: (any SiriusClientDelegate)?
    
    init(transport: any ClientRoleTransport, featureProvider: (any FeatureProvider)) {
        self.id = UUID()
        
        self.clientTransport = transport
        self.featureProvider = featureProvider
        self.channelManager = ChannelManager(session: self)

        self.clientTransport.delegate = self
        
        logger.info("Initialized SiriusClient with ID: \(self.id.uuidString)")
    }
    
    public func setup() async throws {
    }
    
    public func startup() async throws {
        logger.info("Starting up SiriusClient with ID: \(self.id.uuidString)")
        
        try await clientTransport.connect()
    }
    
    public func shutdown() async {
        await clientTransport.disconnect()
    }
}

extension SiriusClient: ClientRoleTransportDelegate {
    func clientTransportDidEstablishConnection(_ transport: any ClientRoleTransport) async {
        logger.info("SiriusClient with ID: \(self.id.uuidString) established connection.")
        do {
            try await self.channelManager.clientOpenMainChannel()
            delegate?.siriusClient(self, didCreateMainChannel: channelManager.mainChannel!)
        } catch {
            logger.error("Failed to open main channel: \(error)")
        }
    }
    
    func clientTransportDidOpenRemoteStream(_ transport: any ClientRoleTransport, stream: Stream) async throws {
        try await channelManager.handleStreamOpen(stream: stream)
    }
    
    func clientTransportDidClose(_ transport: any ClientRoleTransport) async {
        logger.info("SiriusClient with ID: \(self.id.uuidString) transport closed.")
        delegate?.siriusClientDidCloseTransport(self)
    }
    
    func clientTransport(_ transport: any ClientRoleTransport, didEncounterError error: any Error) async {
        logger.error("SiriusClient with ID: \(self.id.uuidString) encountered error: \(error)")
    }

    func clientTransport(_ transport: any ClientRoleTransport, didReceiveServerIdentity identity: ServerIdentityInfo, decisionHandler: @escaping (TrustDecision) -> Void) {
        logger.info("SiriusClient with ID: \(self.id.uuidString) received server identity info for host: \(identity.host).")
        print(identity.alpn)
        print(identity.certificates)
        decisionHandler(.allow)
    }
    
    func clientTransport(_ transport: any ClientRoleTransport, didReceiveNegotiationRequest request: NegotiationRequest, responder: @escaping (NegotiationResponse) -> Void) {
        logger.info("SiriusClient with ID: \(self.id.uuidString) received negotiation request.")
    }
}
