//
//  QUICStream.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation
import Network

class QUICStream: Stream {
    let connection: NWConnection
    let transport: QUICClientTransport
    
    private var receiveTask: Task<Void, Error>?
    
    private(set) var error: Error?
    
    override var id: StreamIdentifier {
        return connection.quicStreamIdentifier!
    }
    
    init(_ connection: NWConnection, transport: QUICClientTransport) {
        self.connection = connection
        self.transport = transport
    }
    
    override func close() async throws {
        receiveTask?.cancel()
        connection.cancel()
        
        transport.unregisterStream(self)
    }
    
    override func write(_ data: Data) async -> Result<UInt64, StreamError> {
        return await withCheckedContinuation { continuation in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(returning: .failure(.notImplemented)) // Map error appropriately
                } else {
                    continuation.resume(returning: .success(UInt64(data.count)))
                }
            })
        }
    }
    
    internal func setup() {
        self.connection.stateUpdateHandler = { state in
            switch (state) {
            case .cancelled:
                self.delegate?.streamDidClose(self, error: self.error)
                break
            case .failed(let error):
                self.error = error
                Task {
                    try! await self.close()
                }
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
                self.error = error
                try! await self.close()
            }
        }
        
        self.connection.start(queue: .main)
    }
    
    private func receiveLoop() async throws {
        while true {
            let result = await receiveNext()
            
            switch result {
            case .success(let data):
                self.delegate?.streamDidReceiveData(self, data: data)
                break
            case .failure(let error):
                throw error
            }
        }
        
    }
    
    private func receiveNext() async -> Result<Data, StreamError> {
        return await withCheckedContinuation { cont in
            // TODO: let length = connection.receive(2)
            //       let opcode = connection.receive(2)
            // ...
        }
    }
}

extension QUICStream: Hashable, Equatable {
    static func == (lhs: QUICStream, rhs: QUICStream) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
