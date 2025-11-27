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
    let transport: ServerRoleClientTransport
    let featureProvider: (any FeatureProvider)
    
    public var channelManager: ChannelManager!
    public var shouldAcceptChannelCreation: Bool = false
    
    init(transport: ServerRoleClientTransport, featureProvider: (any FeatureProvider)) {
        self.transport = transport
        self.featureProvider = featureProvider
        self.channelManager = ChannelManager(session: self)

        self.transport.delegate = self
    }
}

extension ClientSession: ServerRoleClientTransportDelegate {
    func clientTransportDidOpenRemoteStream(_ transport: ServerRoleClientTransport, stream: Stream) async throws {
        try await channelManager.handleStreamOpen(stream: stream)
    }
    
    func clientTransportDidCloseStream(_ transport: ServerRoleClientTransport, stream: Stream) async {
        //
    }
    
    func clientTransportDidClose(_ transport: ServerRoleClientTransport) async {
    }
    
    func clientTransport(_ transport: ServerRoleClientTransport, didEncounterError error: any Error) async {
    }
}
