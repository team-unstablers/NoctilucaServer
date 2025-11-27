//
//  TransportLayer.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation

typealias ServerRoleClientTransportIdentifier = UUID

enum ServerRoleClientTransportError: Error {
    case notImplemented
    case openStreamFailed(error: Error?)
}

protocol ServerRoleClientTransportDelegate: AnyObject {
    /// - NOTE: 리모트에서 스트림을 열었을 때에만 호출됩니다.
    func clientTransportDidOpenRemoteStream(_ transport: ServerRoleClientTransport, stream: Stream) async throws
    func clientTransportDidCloseStream(_ transport: ServerRoleClientTransport, stream: Stream) async
    
    func clientTransportDidClose(_ transport: ServerRoleClientTransport) async
    func clientTransport(_ transport: ServerRoleClientTransport, didEncounterError error: any Error) async
}

class ServerRoleClientTransport {
    weak var delegate: ServerRoleClientTransportDelegate?
    
    var id: ServerRoleClientTransportIdentifier {
        ServerRoleClientTransportIdentifier()
    }
    
    func disconnect() async throws {
        // To be implemented by subclasses
    }
    
    func openStream() async -> Result<Stream, ServerRoleClientTransportError> {
        // To be implemented by subclasses
        return .failure(.notImplemented)
    }
}
