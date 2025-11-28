//
//  SiriusServerApplication.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/24/25.
//

import Foundation

public protocol SiriusServerDelegate: AnyObject {
    func siriusServerDidStart(_ server: SiriusServer)
    func siriusServerDidStop(_ server: SiriusServer)
    func siriusServer(_ server: SiriusServer, didEncounterError error: any Error)
    
    func siriusServerDidAcceptClientSession(_ server: SiriusServer, session: ClientSession)
    func siriusServerDidFailToAcceptClientSession(_ server: SiriusServer, error: any Error)
}

public class SiriusServer {
    let serverTransport: ServerRoleRootTransport
    let featureProvider: (any FeatureProvider)
    
    public let sessions: [ClientSession] = []
    
    public weak var delegate: (any SiriusServerDelegate)?
    
    required init(
        serverTransport: ServerRoleRootTransport,
        featureProvider: (any FeatureProvider)
    ) {
        self.serverTransport = serverTransport
        self.featureProvider = featureProvider
        
        self.serverTransport.delegate = self
    }
    
    public func setup() async throws {
    }
    
    public func startup() async throws {
        try await serverTransport.startup()
    }
    
    public func shutdown() async throws {
        try await serverTransport.shutdown()
    }
}

extension SiriusServer: ServerRoleRootTransportDelegate {
    func serverTransportDidStartListening(_ serverTransport: ServerRoleRootTransport) {
        delegate?.siriusServerDidStart(self)
    }
    
    func serverTransportDidStopListening(_ serverTransport: ServerRoleRootTransport) {
        delegate?.siriusServerDidStop(self)
    }

    func serverTransport(_ serverTransport: ServerRoleRootTransport, didEncounterError error: any Error) {
        delegate?.siriusServer(self, didEncounterError: error)
    }
    
    func serverTransportDidAcceptConnection(_ serverTransport: ServerRoleRootTransport, clientTransport: ServerRoleClientTransport) {
    }
    
    func serverTransportDidFailToAcceptConnection(_ serverTransport: ServerRoleRootTransport, error: any Error) {
    }
}
