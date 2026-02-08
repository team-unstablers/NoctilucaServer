//
//  ClientRoleQUICStream.swift
//  SiriusKit
//
//  Created by Coding Assistant on 03/01/25.
//

import Foundation
import Network

import Atomics
import SiriusKitCore

class ClientRoleQUICStream: SiriusKitCore.Stream {
    let connection: NWConnection
    let transport: ClientRoleQUICTransport
    private let queue: DispatchQueue

    private var receiveTask: Task<Void, Error>?
    private let isClosed = ManagedAtomic(false)

    init(_ connection: NWConnection, transport: ClientRoleQUICTransport, queue: DispatchQueue, identifier: StreamIdentifier = StreamIdentifier()) {
        self.connection = connection
        self.transport = transport
        self.queue = queue

        super.init()

        self.id = identifier
    }

    override func close() async throws {
        if self.isClosed.load(ordering: .acquiring) {
            return
        }

        await finalize(event: .closed)
    }

    override func write(_ data: Data) async -> Result<UInt32, StreamError> {
        return await withCheckedContinuation { continuation in
            // swiftlint:disable:next force_cast
            var metadata = self.connection.metadata(definition: NWProtocolQUIC.definition) as! NWProtocolQUIC.Metadata
            var context = NWConnection.ContentContext(
                identifier: "quic",
                priority: 1.0,
                antecedent: .defaultMessage,
                metadata: [metadata]
            )
            
            connection.send(content: data, contentContext: context, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(returning: .failure(.notImplemented)) // Map error appropriately
                } else {
                    continuation.resume(returning: .success(UInt32(data.count)))
                }
            })
        }
    }
    
    private func sendFIN() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }

    internal func setup(_ readyHandler: (() -> Void)?) {
        self.connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            switch state {
            case .cancelled:
                Task { await self.finalize(event: .closed) }
            case .failed(let error):
                Task {
                    if let delegate = self.transport.delegate {
                        await delegate.clientTransport(self.transport, didEncounterError: error)
                    }
                    await self.finalize(event: .error(error))
                }
            case .ready:
                readyHandler?()
            default:
                break
            }
        }
    }

    internal func start() {
        self.receiveTask = Task {
            do {
                try await self.receiveLoop()
            } catch {
                if let streamError = error as? StreamError, case .endOfStream = streamError {
                    await self.finalize(event: .closed)
                    return
                }

                await self.finalize(event: .error(error))
            }
        }

        self.connection.start(queue: self.queue)
    }

    private func receiveLoop() async throws {
        while true {
            // read header
            let rawHeader = try (await self.read(minSize: 6, maxSize: 6)).get()

            let opcode = rawHeader.subdata(in: 0..<2).withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
            let length = rawHeader.subdata(in: 2..<6).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            
            // TODO: fragmented read
            let payload = (length > 0) ?
                try (await self.read(minSize: Int(length), maxSize: Int(length))).get() :
                Data()

            let frame = SiriusFrame(opcode: MessageOpcode(rawValue: opcode),
                                    length: length,
                                    data: payload)
            

            self.continuation.yield(with: .success(.frame(frame)))
        }

    }

    private func read(minSize: Int, maxSize: Int) async -> Result<Data, Error> {
        return await withCheckedContinuation { cont in
            self.connection.receive(minimumIncompleteLength: minSize, maximumLength: maxSize) { content, context, complete, error in
                if complete {
                    cont.resume(returning: .failure(StreamError.endOfStream))
                } else if let error = error {
                    cont.resume(returning: .failure(error)) // Map error appropriately
                } else if let content = content {
                    cont.resume(returning: .success(content))
                } else {
                    cont.resume(returning: .failure(StreamError.endOfStream))
                }
            }
        }
    }

    private func finalize(event: StreamEvent) async {
        if self.isClosed.exchange(true, ordering: .acquiring) {
            return
        }

        self.connection.cancel()
        receiveTask?.cancel()

        self.continuation.yield(with: .success(event))
        self.continuation.finish()

        await transport.unregisterStream(self)
    }
}

extension ClientRoleQUICStream: Hashable, Equatable {
    static func == (lhs: ClientRoleQUICStream, rhs: ClientRoleQUICStream) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
