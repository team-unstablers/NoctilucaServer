//
//  ClientRoleTransport.swift
//  SiriusKit
//
//  Created by Coding Assistant on 03/01/25.
//

import Foundation
import Security

typealias ClientRoleTransportIdentifier = TransportLayerIdentifier

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
    func clientTransportDidEstablishConnection(_ transport: any ClientRoleTransport) async
    func clientTransportDidOpenRemoteStream(_ transport: any ClientRoleTransport, stream: Stream) async throws
    func clientTransportDidClose(_ transport: any ClientRoleTransport) async
    func clientTransport(_ transport: any ClientRoleTransport, didEncounterError error: any Error) async

    func clientTransport(_ transport: any ClientRoleTransport, didReceiveServerIdentity identity: ServerIdentityInfo, decisionHandler: @escaping (TrustDecision) -> Void)
    func clientTransport(_ transport: any ClientRoleTransport, didReceiveNegotiationRequest request: NegotiationRequest, responder: @escaping (NegotiationResponse) -> Void)
}

protocol ClientRoleTransport: TransportLayer, Hashable where ID == ClientRoleTransportIdentifier {
    var delegate: ClientRoleTransportDelegate? { get set }

    func connect() async throws
}

extension ClientRoleTransport {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
