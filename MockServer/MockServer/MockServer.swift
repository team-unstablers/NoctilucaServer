//
//  MockServer.swift
//  MockServer
//
//  Created by Gyuhwan Park on 2/13/26.
//

import Foundation
import SiriusKit

import SwiftMsQuicHelper

class MockServer {
    private let logger = SiriusLogger(category: "MockServer", subsystem: "app.noctiluca.mockserver")

    let projectionSource: URL
    let port: UInt16

    private var server: SiriusServer?
    private var shutdownContinuation: CheckedContinuation<Void, Never>?
    private var clients: [UUID: MockClientSession] = [:]

    init(projectionSource: URL, port: UInt16) {
        self.projectionSource = projectionSource
        self.port = port
    }

    func startup() async throws {
        SiriusLogger.configure(minimumLevel: .debug)

        logger.info("Starting MockServer with source: \(self.projectionSource.path), port: \(self.port)")

        let featureProvider = MockFeatureProvider(projectionSource: projectionSource)

        let result = SiriusServerBuilder()
            .useFeatureProvider(featureProvider)
            .useTransportProtocol(.quic(
                implementation: TransportLayerImplementation.msQuic.identifier,
                port: port,
                identitySource: .keychain(label: "babo")
            ))
            .build()

        let server = try result.get()
        server.delegate = self
        self.server = server
        
        SwiftMsQuicAPI.open()

        try await server.setup()
        print("OK")
        try await server.startup()
    }

    func waitForShutdown() async {
        // SIGINT / SIGTERM 핸들링
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)

        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        sigintSource.setEventHandler { [weak self] in
            Task {
                await self?.shutdown()
            }
        }
        sigtermSource.setEventHandler { [weak self] in
            Task {
                await self?.shutdown()
            }
        }

        sigintSource.resume()
        sigtermSource.resume()

        await withCheckedContinuation { continuation in
            self.shutdownContinuation = continuation
        }

        sigintSource.cancel()
        sigtermSource.cancel()
    }

    func shutdown() async {
        logger.info("Shutting down MockServer...")

        // 모든 클라이언트 세션 정리
        for (_, session) in clients {
            await session.close()
        }
        clients.removeAll()

        do {
            try await server?.shutdown()
        } catch {
            logger.error("Error during shutdown: \(error)")
        }

        shutdownContinuation?.resume()
        shutdownContinuation = nil
    }
}

extension MockServer: SiriusServerDelegate {
    func siriusServerDidStart(_ server: SiriusServer) {
        logger.info("MockServer is now running on port \(self.port).")
    }

    func siriusServerDidStop(_ server: SiriusServer) {
        logger.info("MockServer has stopped.")
        shutdownContinuation?.resume()
        shutdownContinuation = nil
    }

    func siriusServer(_ server: SiriusServer, didEncounterError error: any Error) {
        logger.error("MockServer encountered an error: \(error)")
    }

    func siriusServerDidAcceptClientSession(_ server: SiriusServer, session: ClientSession) {
        let mockSession = MockClientSession(
            session: session,
            projectionSource: projectionSource
        )
        mockSession.delegate = self
        mockSession.initialize()

        clients[session.id] = mockSession
        logger.info("Accepted client session: \(session.id)")
    }

    func siriusServerDidFailToAcceptClientSession(_ server: SiriusServer, error: any Error) {
        logger.error("Failed to accept client session: \(error)")
    }
}

extension MockServer: MockClientSessionDelegate {
    func mockClientSessionDidClose(_ session: MockClientSession) {
        clients[session.id] = nil
        logger.info("Client session closed: \(session.id)")
    }
}
