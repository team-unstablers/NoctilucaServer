//
//  ServerRoleRootTransport.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

protocol ServerRoleRootTransportError: Error {}

protocol ServerRoleRootTransportDelegate: AnyObject {
    /// TODO: Add parameters for listening info
    func serverTransportDidStartListening(_ serverTransport: ServerRoleRootTransport)
    func serverTransportDidStopListening(_ serverTransport: ServerRoleRootTransport)
    func serverTransport(_ serverTransport: ServerRoleRootTransport, didEncounterError error: any Error)

    func serverTransportDidAcceptConnection(_ serverTransport: ServerRoleRootTransport, clientTransport: any ServerRoleClientTransport)
    func serverTransportDidFailToAcceptConnection(_ serverTransport: ServerRoleRootTransport, error: Error)
}

protocol ServerRoleRootTransport: AnyObject {
    var delegate: ServerRoleRootTransportDelegate? { get set }

    func startup() async throws

    func shutdown() async throws
}
