//
//  ClientRoleQUICStream.swift
//  SiriusKit
//
//  Created by Coding Assistant on 03/01/25.
//

import Foundation
import Network

import Atomics

class ClientRoleQUICStream: Stream {
    let connection: NWConnection
    let transport: ClientRoleQUICTransport
    
    private var receiveTask: Task<Void, Error>?
    
    private var _id: StreamIdentifier = StreamIdentifier.max
    override var id: StreamIdentifier { _id }

    init(_ connection: NWConnection, transport: ClientRoleQUICTransport) {
        self.connection = connection
        self.transport = transport
    }
    
    override func close() async throws {
        receiveTask?.cancel()
        connection.cancel()
        
        transport.unregisterStream(self)
    }
    
    override func write(_ data: Data) async -> Result<UInt32, StreamError> {
        let byteCount = UInt64(data.count)
        writeBackPressure.wrappingIncrement(by: byteCount, ordering: .relaxed)
        
        defer {
            self.writeBackPressure.wrappingDecrement(by: UInt64(data.count), ordering: .relaxed)
        }

        return await withCheckedContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(returning: .failure(.notImplemented)) // Map error appropriately
                } else {
                    continuation.resume(returning: .success(UInt32(data.count)))
                }
            })
        }
    }
    
    internal func setup(_ readyHandler: (() -> Void)?) {
        self.connection.stateUpdateHandler = { state in
            switch (state) {
            case .cancelled:
                self.continuation.yield(with: .success(.closed))
                self.continuation.finish()
                Task {
                    await self.transport.delegate?.clientTransportDidClose(self.transport)
                }
                break
            case .failed(let error):
                self.continuation.yield(with: .success(.error(error)))
                Task {
                    await self.transport.delegate?.clientTransport(self.transport, didEncounterError: error)
                    try! await self.close()
                }
                break
            case .ready:
                self._id = self.connection.quicStreamIdentifier!
                readyHandler?()
                break
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
                self.continuation.yield(with: .success(.error(error)))
                try! await self.close()
            }
        }
        
        self.connection.start(queue: .main)
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
            self.connection.receive(minimumIncompleteLength: minSize, maximumLength: maxSize) { content, contentContext, eos, error in
                if let error = error {
                    cont.resume(returning: .failure(error)) // Map error appropriately
                } else if let content = content {
                    print("ClientRoleQUICStream \(self.id) received data of size: \(content.count), eos: \(eos)")
                    cont.resume(returning: .success(content))
                } else {
                    // EOS
                    fatalError("unexpected nil content")
                }
            }
        }
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
