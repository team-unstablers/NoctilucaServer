//
//  TransportLayer.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation

typealias ClientTransportIdentifier = UUID

enum ClientTransportError: Error {
    case notImplemented
    case openStreamFailed(error: Error?)
}

protocol ClientTransportDelegate: AnyObject {
    /// - NOTE: 리모트에서 스트림을 열었을 때에만 호출됩니다.
    func clientTransportDidOpenStream(_ transport: ClientTransport, stream: Stream) async throws
    func clientTransportDidCloseStream(_ transport: ClientTransport, stream: Stream) async
    
    func clientTransportDidClose(_ transport: ClientTransport, error: Error?) async
}

class ClientTransport {
    weak var delegate: ClientTransportDelegate?
    
    open var id: ClientTransportIdentifier {
        ClientTransportIdentifier()
    }
    
    open func disconnect() async throws {
        // To be implemented by subclasses
    }
    
    open func openStream() async -> Result<Stream, ClientTransportError> {
        // To be implemented by subclasses
        return .failure(.notImplemented)
    }
}

