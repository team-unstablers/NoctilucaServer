//
//  SiriusServerApplication.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/24/25.
//

import Foundation
import SiriusKitCore

public protocol SiriusServerDelegate: AnyObject {
    func siriusServerDidStart(_ server: SiriusServer)
    func siriusServerDidStop(_ server: SiriusServer)
    func siriusServer(_ server: SiriusServer, didEncounterError error: any Error)

    func siriusServerDidAcceptClientSession(_ server: SiriusServer, session: ClientSession)
    func siriusServerDidFailToAcceptClientSession(_ server: SiriusServer, error: any Error)
}

public class SiriusServer {
    let serverTransport: ServerRoleRootTransport
    let featureProvider: (any FeatureProvider)

    private let sessionsLock = NSLock()
    private var _sessions: [ClientSession] = []

    public var sessions: [ClientSession] {
        sessionsLock.withLock { _sessions }
    }

    public weak var delegate: (any SiriusServerDelegate)?

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
        sessionsLock.withLock {
            _sessions.append(session)
        }
    }

    private func removeSession(id: UUID) {
        sessionsLock.withLock {
            _sessions.removeAll { $0.id == id }
        }
    }

    private func takeSessionsSnapshot() -> [ClientSession] {
        sessionsLock.withLock {
            let snapshot = _sessions
            _sessions.removeAll()
            return snapshot
        }
    }
}

extension SiriusServer: ServerRoleRootTransportDelegate {
    func serverTransportDidStartListening(_ serverTransport: ServerRoleRootTransport) {
        delegate?.siriusServerDidStart(self)
    }

    func serverTransportDidStopListening(_ serverTransport: ServerRoleRootTransport) {
        delegate?.siriusServerDidStop(self)
    }

    func serverTransport(_ serverTransport: ServerRoleRootTransport, didEncounterError error: any Error) {
        delegate?.siriusServer(self, didEncounterError: error)
    }

    func serverTransportDidAcceptConnection(_ serverTransport: ServerRoleRootTransport, clientTransport: any ServerRoleClientTransport) {
        self.createClientSession(clientTransport)
    }

    func serverTransportDidFailToAcceptConnection(_ serverTransport: ServerRoleRootTransport, error: any Error) {
    }
}

extension SiriusServer: ClientSessionLifecycleDelegate {
    func clientSessionDidClose(_ session: ClientSession) {
        removeSession(id: session.id)
    }
}
