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
    let serverTransport: ServerTransport
    let featureProvider: (any FeatureProvider)
    
    let sessions: [ClientSession] = []
    
    weak var delegate: (any SiriusServerDelegate)?
    
    required init(
        serverTransport: ServerTransport,
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

extension SiriusServer: ServerTransportDelegate {
    func serverTransportDidStartListening(_ serverTransport: ServerTransport) {
    }
    
    func serverTransportDidStopListening(_ serverTransport: ServerTransport) {
    }
    
    func serverTransportDidAcceptConnection(_ serverTransport: ServerTransport, clientTransport: ClientTransport) {
    }
    
    func serverTransportDidFailToAcceptConnection(_ serverTransport: ServerTransport, error: any Error) {
    }
}
