//
//  SiriusServerApplication.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/24/25.
//

import Foundation
import SiriusKitCore

public protocol SiriusServerDelegate: AnyObject, Sendable {
    func siriusServerDidStart(_ server: SiriusServer)
    func siriusServerDidStop(_ server: SiriusServer)
    func siriusServer(_ server: SiriusServer, didEncounterError error: any Error)

    func siriusServerDidAcceptClientSession(_ server: SiriusServer, session: ClientSession)
    func siriusServerDidFailToAcceptClientSession(_ server: SiriusServer, error: any Error)
}

public actor SiriusServer: Sendable {
    let serverTransport: ServerRoleRootTransport
    let featureProvider: (any FeatureProvider)

    private(set) public var sessions: [ClientSession] = []

    public weak var delegate: (any SiriusServerDelegate)?

    init(
        serverTransport: ServerRoleRootTransport,
        featureProvider: (any FeatureProvider)
    ) {
        self.serverTransport = serverTransport
        self.featureProvider = featureProvider

        self.serverTransport.delegate = self
    }
    
    public func setDelegate(_ delegate: (any SiriusServerDelegate)?) {
        self.delegate = delegate
    }

    public func setup() async throws {
    }

    public func startup() async throws {
        try await serverTransport.startup()
    }

    public func shutdown() async throws {
        let sessionSnapshot = self.takeSessionsSnapshot()

        for session in sessionSnapshot {
            await session.close()
        }

        try await serverTransport.shutdown()
    }

    private func createClientSession(_ transport: any ServerRoleClientTransport) {
        guard !transport.isClosed else {
            return
        }

        let eventLoggerContext = transport.eventLoggerContext()
        let session = ClientSession(id: UUID(), transport: transport, featureProvider: featureProvider, eventLoggerContext: eventLoggerContext)
        session.lifecycleDelegate = self

        appendSession(session)
        self.delegate?.siriusServerDidAcceptClientSession(self, session: session)
        session.activate()

        if transport.isClosed {
            Task {
                await session.close()
            }
        }
    }

    private func appendSession(_ session: ClientSession) {
        sessions.append(session)
    }

    private func removeSession(id: UUID) {
        sessions.removeAll { $0.id == id }
    }

    private func takeSessionsSnapshot() -> [ClientSession] {
        let snapshot = sessions
        
        // 잠깐, 왜 여기서 removeAll()을 해?
        sessions.removeAll()
        return snapshot
    }
}

extension SiriusServer: ServerRoleRootTransportDelegate {
    nonisolated func serverTransportDidStartListening(_ serverTransport: ServerRoleRootTransport) {
        Task {
            await self.delegate?.siriusServerDidStart(self)
        }
    }

    nonisolated func serverTransportDidStopListening(_ serverTransport: ServerRoleRootTransport) {
        Task {
            await self.delegate?.siriusServerDidStop(self)
        }
    }

    nonisolated func serverTransport(_ serverTransport: ServerRoleRootTransport, didEncounterError error: any Error) {
        Task {
            await self.delegate?.siriusServer(self, didEncounterError: error)
        }
    }

    nonisolated func serverTransportDidAcceptConnection(_ serverTransport: ServerRoleRootTransport, clientTransport: any ServerRoleClientTransport) {
        Task {
            await self.createClientSession(clientTransport)
        }
    }

    nonisolated func serverTransportDidFailToAcceptConnection(_ serverTransport: ServerRoleRootTransport, error: any Error) {
    }
}

extension SiriusServer: ClientSessionLifecycleDelegate {
    nonisolated func clientSessionDidClose(_ session: ClientSession) {
        Task {
            await self.removeSession(id: session.id)
        }
    }
}
