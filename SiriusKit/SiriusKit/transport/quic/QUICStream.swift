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
    
    override func write(_ data: Data) async -> Result<UInt32, StreamError> {
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
                break
            case .failed(let error):
                self.continuation.yield(with: .success(.error(error)))
                Task {
                    try! await self.close()
                }
                break
            case .ready:
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
            let result = await receiveNext()
            
            switch result {
            case .success(let data):
                if let data = data {
                    self.continuation.yield(with: .success(.data(data)))
                }
                break
            case .failure(let error):
                throw error
            }
        }
        
    }
    
    private func receiveNext() async -> Result<Data?, Error> {
        return await withCheckedContinuation { cont in
            //                      vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv: 이거 fragmentation이나 그런거 걱정 안 해도 되나...? 아 괜히 쫄리네 ㅠ_ㅠ
            self.connection.receive(minimumIncompleteLength: 6, maximumLength: Int(Int32.max)) { content, contentContext, eos, error in
                if let error = error {
                    cont.resume(returning: .failure(error)) // Map error appropriately
                } else if let content = content {
                    print("QUICStream \(self.id) received data of size: \(content.count), eos: \(eos)")
                    cont.resume(returning: .success(content))
                } else {
                    // FIXME: 로직 개선
                    cont.resume(returning: .success(nil)) // No data received
                }
            }
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
