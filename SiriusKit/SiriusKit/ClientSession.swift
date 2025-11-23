//
//  ClientConnection.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation

public protocol ClientSessionDelegate: AnyObject {
    func clientSessionDidCreateMainChannel(_ session: ClientSession, mainChannel: MainChannel)
}

public class ClientSession {
    let transport: ClientTransport
    let featureProvider: (any FeatureProvider)
    
    public var channelManager: ChannelManager!
    public var shouldAcceptChannelCreation: Bool = false
    
    init(transport: ClientTransport, featureProvider: (any FeatureProvider)) {
        self.transport = transport
        self.featureProvider = featureProvider
        self.channelManager = ChannelManager(session: self)

        self.transport.delegate = self
    }
}

extension ClientSession: ClientTransportDelegate {
    func clientTransportDidOpenStream(_ transport: ClientTransport, stream: Stream) async throws {
        try await channelManager.handleStreamOpen(stream: stream)
    }
    
    func clientTransportDidCloseStream(_ transport: ClientTransport, stream: Stream) {
        //
    }
    
    func clientTransportDidClose(_ transport: ClientTransport, error: (any Error)?) {
    }
}
