//
//  ServerTransport.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

protocol ServerTransportError: Error {}

protocol ServerTransportDelegate: AnyObject {
    /// TODO: Add parameters for listening info
    func serverTransportDidStartListening(_ serverTransport: ServerTransport)
    func serverTransportDidStopListening(_ serverTransport: ServerTransport)
    func serverTransport(_ serverTransport: ServerTransport, didEncounterError error: any Error)
    
    func serverTransportDidAcceptConnection(_ serverTransport: ServerTransport, clientTransport: ClientTransport)
    func serverTransportDidFailToAcceptConnection(_ serverTransport: ServerTransport, error: Error)
}

class ServerTransport {
    weak var delegate: ServerTransportDelegate?
    
    open func startup() async throws {
    }
    
    open func shutdown() async throws {
    }
}
