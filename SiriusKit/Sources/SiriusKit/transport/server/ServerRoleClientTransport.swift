//
//  TransportLayer.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation
import SiriusKitCore

typealias ServerRoleClientTransportIdentifier = TransportLayerIdentifier

protocol ServerRoleClientTransportDelegate: AnyObject {
    /// - NOTE: 리모트에서 스트림을 열었을 때에만 호출됩니다.
    func clientTransportDidOpenRemoteStream(_ transport: any ServerRoleClientTransport, stream: SiriusKitCore.Stream) async throws
    func clientTransportDidCloseStream(_ transport: any ServerRoleClientTransport, stream: SiriusKitCore.Stream) async

    func clientTransportDidClose(_ transport: any ServerRoleClientTransport) async
    func clientTransport(_ transport: any ServerRoleClientTransport, didEncounterError error: any Error) async
}

protocol ServerRoleClientTransport: TransportLayer, Hashable where ID == ServerRoleClientTransportIdentifier {
    var delegate: ServerRoleClientTransportDelegate? { get set }

    var remoteEndpoint: SREndpoint? { get }
    
    func issueResumeTicket() async throws
}

extension ServerRoleClientTransport {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
