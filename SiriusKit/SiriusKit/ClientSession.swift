//
//  ClientConnection.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation

public class ClientSession {
    let transport: ClientTransport
    let featureProvider: (any FeatureProvider)
    
    public let channelManager: ChannelManager
    
    init(transport: ClientTransport, featureProvider: (any FeatureProvider)) {
        self.transport = transport
        self.transport.delegate = self
        
        self.featureProvider = featureProvider
        
        self.channelManager = ChannelManager(session: self)
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
