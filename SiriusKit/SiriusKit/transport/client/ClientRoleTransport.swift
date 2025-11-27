//
//  ClientRoleTransport.swift
//  SiriusKit
//
//  Created by Coding Assistant on 03/01/25.
//

import Foundation
import Security

typealias ClientRoleTransportIdentifier = UUID

enum ClientRoleTransportError: Error {
    case notImplemented
    case connectionFailed(error: Error?)
    case openStreamFailed(error: Error?)
    case mainChannelOpenFailed
}

enum TrustDecision {
    case allow
    case deny(reason: Error?)
    case deferToApp
}

struct ServerIdentityInfo {
    let host: String
    let port: UInt16
    let alpn: String
    let certificates: [SecCertificate]
    let leafApplicationLabel: Data?
    let notBefore: Date?
    let notAfter: Date?
}

struct NegotiationRequest {
    let supportedAlpns: [String]
    let allowZeroRtt: Bool
}

struct NegotiationResponse {
    let selectedAlpn: String
    let enableZeroRtt: Bool
}

protocol ClientRoleTransportDelegate: AnyObject {
    func clientTransportDidOpenMainStream(_ transport: ClientRoleTransport, stream: Stream) async throws
    func clientTransportDidClose(_ transport: ClientRoleTransport) async
    func clientTransport(_ transport: ClientRoleTransport, didEncounterError error: any Error) async
    
    func clientTransport(_ transport: ClientRoleTransport, didReceiveServerIdentity identity: ServerIdentityInfo, decisionHandler: @escaping (TrustDecision) -> Void)
    func clientTransport(_ transport: ClientRoleTransport, didReceiveNegotiationRequest request: NegotiationRequest, responder: @escaping (NegotiationResponse) -> Void)
}

class ClientRoleTransport {
    weak var delegate: ClientRoleTransportDelegate?
    
    var id: ClientRoleTransportIdentifier {
        ClientRoleTransportIdentifier()
    }
    
    func connect() async throws {
        // To be implemented by subclasses
    }
    
    func disconnect() async throws {
        // To be implemented by subclasses
    }
    
    func openStream() async -> Result<Stream, ClientRoleTransportError> {
        // To be implemented by subclasses
        return .failure(.notImplemented)
    }
}
