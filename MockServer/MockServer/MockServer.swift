//
//  MockServer.swift
//  MockServer
//
//  Created by Gyuhwan Park on 2/13/26.
//

import Foundation
import SiriusKit

import SwiftMsQuic

actor MockServer {
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
                identity: PEMFileQUICServerIdentity(
                    using: "/Users/cheesekun/works/noctiluca/swift-msquic/server.crt",
                    key: "/Users/cheesekun/works/noctiluca/swift-msquic/server.key"
                )
            ))
            .build()

        let server = try result.get()
        await server.setDelegate(self)
        self.server = server

        SwiftMsQuicAPI.open()

        try await server.setup()
        try await server.startup()
        print("OK")
    }

    func waitForShutdown() async {
        // SIGINT / SIGTERM 핸들링
        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)

        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        signal(SIGPIPE, SIG_IGN)

        sigintSource.setEventHandler { [weak self] in
            guard let strongSelf = self else { return }
            Task { [strongSelf] in
                await strongSelf.shutdown()
                exit(1)
            }
        }
        sigtermSource.setEventHandler { [weak self] in
            guard let strongSelf = self else { return }
            Task { [strongSelf] in
                await strongSelf.shutdown()
                exit(1)
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

    // MARK: - Internal helpers (called from delegate hops)

    fileprivate func didAcceptSession(_ session: ClientSession) {
        let mockSession = MockClientSession(
            session: session,
            projectionSource: projectionSource
        )
        Task { [weak self] in
            guard let self else { return }
            await mockSession.setDelegate(self)
            await mockSession.initialize()
        }

        clients[session.id] = mockSession
        logger.info("Accepted client session: \(session.id)")
    }

    fileprivate func didCloseSession(_ id: UUID) {
        clients[id] = nil
        logger.info("Client session closed: \(id)")
    }

    fileprivate func didStop() {
        shutdownContinuation?.resume()
        shutdownContinuation = nil
    }
}

extension MockServer: SiriusServerDelegate {
    nonisolated func siriusServerDidStart(_ server: SiriusServer) {
        Task { [weak self] in
            await self?.logger.info("MockServer is now running.")
        }
    }

    nonisolated func siriusServerDidStop(_ server: SiriusServer) {
        Task { [weak self] in
            await self?.didStop()
        }
    }

    nonisolated func siriusServer(_ server: SiriusServer, didEncounterError error: any Error) {
        Task { [weak self] in
            await self?.logger.error("MockServer encountered an error: \(error)")
        }
    }

    nonisolated func siriusServerDidAcceptClientSession(_ server: SiriusServer, session: ClientSession) async {
        await self.didAcceptSession(session)
    }

    nonisolated func siriusServerDidFailToAcceptClientSession(_ server: SiriusServer, error: any Error) {
        Task { [weak self] in
            await self?.logger.error("Failed to accept client session: \(error)")
        }
    }
}

extension MockServer: MockClientSessionDelegate {
    nonisolated func mockClientSessionDidClose(_ session: MockClientSession) {
        let id = session.id
        Task { [weak self] in
            await self?.didCloseSession(id)
        }
    }
}
