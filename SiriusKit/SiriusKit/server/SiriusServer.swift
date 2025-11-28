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
    
    func siriusServerDidAcceptClientSession(_ server: SiriusServer, session: ClientSession)
    func siriusServerDidFailToAcceptClientSession(_ server: SiriusServer, error: any Error)
}

public class SiriusServer {
    let serverTransport: ServerRoleRootTransport
    let featureProvider: (any FeatureProvider)
    
    let sessions: [ClientSession] = []
    
    weak var delegate: (any SiriusServerDelegate)?
    
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
    }
    
    func serverTransportDidStopListening(_ serverTransport: ServerRoleRootTransport) {
    }

    func serverTransport(_ serverTransport: ServerRoleRootTransport, didEncounterError error: any Error) {
    }
    
    func serverTransportDidAcceptConnection(_ serverTransport: ServerRoleRootTransport, clientTransport: ServerRoleClientTransport) {
    }
    
    func serverTransportDidFailToAcceptConnection(_ serverTransport: ServerRoleRootTransport, error: any Error) {
    }
}
