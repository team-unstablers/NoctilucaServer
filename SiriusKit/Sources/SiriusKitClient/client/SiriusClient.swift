//
//  ClientConnection.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation
import SiriusKitCore

import Atomics

public protocol SiriusClientDelegate: AnyObject {
    func siriusClient(_ client: SiriusClient, didCreateMainChannel mainChannel: MainChannel)
    func siriusClient(_ client: SiriusClient, didEncounterError error: (any Error))
    func siriusClientDidCloseTransport(_ client: SiriusClient)
}

public class SiriusClient: SiriusSession, @unchecked Sendable {
    private let logger = SiriusLogger(category: "SiriusClient")

    public let id: UUID
    
    private var isFinalized = ManagedAtomic<Bool>(false)

    let clientTransport: any ClientRoleTransport
    package var transport: any TransportLayer { clientTransport }

    package let featureProvider: (any FeatureProvider)
    
    public var channelManager: ChannelManager!
    public var shouldAcceptChannelCreation: Bool = false

    public weak var delegate: (any SiriusClientDelegate)?

    // MARK: Computed Properties
    
    public var endpoint: SREndpoint {
        clientTransport.endpoint
    }
    
    public var identity: ServerIdentity? {
        clientTransport.identity
    }
    
    public var identityValidationPolicy: ServerIdentityValidationPolicy {
        get { clientTransport.identityValidationPolicy }
        set { clientTransport.identityValidationPolicy = newValue }
    }

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
        guard isFinalized.compareExchange(expected: false, desired: true, ordering: .acquiring).original == false else {
            return
        }
        
        shouldAcceptChannelCreation = false
        await channelManager.teardownAllChannels()
        
        // HACK: 별도 Task로 분리하지 않으면 여기서 데드락 걸림
        Task.detached { [clientTransport] in
            await clientTransport.disconnect()
        }
    }
}

extension SiriusClient: ClientRoleTransportDelegate {
    func clientTransportDidEstablishConnection(_ transport: any ClientRoleTransport) async {
        logger.info("SiriusClient with ID: \(self.id.uuidString) established connection.")
        do {
            try await self.channelManager.clientOpenMainChannel()
            guard let mainChannel = await channelManager.mainChannel else {
                logger.error("Main channel was not created after connection establishment.")
                return
            }
            delegate?.siriusClient(self, didCreateMainChannel: mainChannel)
        } catch {
            logger.error("Failed to open main channel: \(error)")
        }
    }

    func clientTransportDidOpenRemoteStream(_ transport: any ClientRoleTransport, stream: SiriusKitCore.Stream) async throws {
        try await channelManager.handleStreamOpen(stream: stream)
    }

    func clientTransportDidClose(_ transport: any ClientRoleTransport) async {
        logger.info("SiriusClient with ID: \(self.id.uuidString) transport closed.")
        delegate?.siriusClientDidCloseTransport(self)
    }

    func clientTransport(_ transport: any ClientRoleTransport, didEncounterError error: any Error) async {
        logger.error("SiriusClient with ID: \(self.id.uuidString) encountered error: \(error)")
        delegate?.siriusClient(self, didEncounterError: error)
    }

    func clientTransport(_ transport: any ClientRoleTransport, didReceiveNegotiationRequest request: NegotiationRequest, responder: @escaping (NegotiationResponse) -> Void) {
        logger.info("SiriusClient with ID: \(self.id.uuidString) received negotiation request.")
    }
}
