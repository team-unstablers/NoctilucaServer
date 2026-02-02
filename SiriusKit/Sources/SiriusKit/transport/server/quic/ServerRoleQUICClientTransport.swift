//
//  ServerRoleQUICClientTransport.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation
import Network

enum ServerRoleQUICClientTransportError: Error {
}

actor ServerRoleQUICClientTransport: ServerRoleClientTransport {
    nonisolated let id: ServerRoleClientTransportIdentifier
    nonisolated(unsafe) weak var delegate: ServerRoleClientTransportDelegate?

    let connectionGroup: NWConnectionGroup
    let serverTransport: ServerRoleQUICRootTransport

    private var streams: [StreamIdentifier: ServerRoleQUICStream] = [:]

    private let queue = DispatchQueue(label: "io.siriuskit.quic.server.client")

    private var isFinalized: Bool = false

    nonisolated var remoteAddress: String? {
        guard let endpoint = self.connectionGroup.descriptor.members.first else {
            return nil
        }

        return endpoint.asString()
    }

    init(_ connectionGroup: NWConnectionGroup, serverTransport: ServerRoleQUICRootTransport, id: ServerRoleClientTransportIdentifier) {
        self.id = id

        self.serverTransport = serverTransport
        self.connectionGroup = connectionGroup
    }

    func disconnect() async {
        guard !isFinalized else {
            return
        }

        self.isFinalized = true

        let snapshot = Array(self.streams.values)
        self.streams.removeAll()

        for stream in snapshot {
            try? await stream.close()
        }

        self.connectionGroup.cancel()

        await self.delegate?.clientTransportDidClose(self)
        await self.serverTransport.unregisterClientTransport(self)
    }

    func openStream() async -> Result<Stream, TransportLayerError> {
        return await withCheckedContinuation { continuation in
            guard let connection = NWConnection(from: self.connectionGroup) else {
                continuation.resume(returning: .failure(.openStreamFailed(error: nil)))
                return
            }

            let stream = ServerRoleQUICStream(connection, transport: self, queue: self.queue)

            stream.setup { [weak self, weak stream] in
                guard let self, let stream else { return }

                Task {
                    await self.registerStream(stream)
                    continuation.resume(returning: .success(stream))
                }
            }

            stream.start()
        }
    }

    internal func setup() {
        self.connectionGroup.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            switch state {
            case .failed(let error):
                Task {
                    if let delegate = self.delegate {
                        await delegate.clientTransport(self, didEncounterError: error)
                    }
                    await self.disconnect()
                }
            case .cancelled:
                Task {
                    await self.disconnect()
                }
            default:
                break
            }
        }

        self.connectionGroup.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.handleNewConnection(connection) }
        }
    }

    internal func start() {
        self.connectionGroup.start(queue: self.queue)
    }

    private func handleNewConnection(_ connection: NWConnection) async {
        let stream = ServerRoleQUICStream(connection, transport: self, queue: self.queue)

        stream.setup { [weak self] in
            guard let self else { return }

            Task { await self.registerStream(stream) }

            if let delegate = self.delegate {
                Task {
                    do {
                        try await delegate.clientTransportDidOpenRemoteStream(self, stream: stream)
                    } catch {
                        await delegate.clientTransport(self, didEncounterError: error)
                    }
                }
            }
        }
        stream.start()
    }

    internal func registerStream(_ stream: ServerRoleQUICStream) {
        assert(stream.connection.state == .ready)

        let streamId = stream.id
        guard !self.streams.keys.contains(streamId) else {
            return
        }

        self.streams.updateValue(stream, forKey: streamId)
    }

    internal func unregisterStream(_ stream: ServerRoleQUICStream) {
        guard self.streams.keys.contains(stream.id) else {
            return
        }

        self.streams.removeValue(forKey: stream.id)
    }
}

extension ServerRoleQUICClientTransport: Hashable, Equatable {
    nonisolated static func == (lhs: ServerRoleQUICClientTransport, rhs: ServerRoleQUICClientTransport) -> Bool {
        return lhs.id == rhs.id
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
