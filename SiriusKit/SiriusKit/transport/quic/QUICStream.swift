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
    
    internal func setup() {
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
        // FIXME: isComplete 붙어있는거 보면 데이터 분명 프레그멘테이션 처리 필요할듯
        return await withCheckedContinuation { cont in
            self.connection.receiveMessage { content, contentContext, isComplete, error in
                if let error = error {
                    cont.resume(returning: .failure(error)) // Map error appropriately
                } else if let content = content {
                    assert(isComplete, "아직 fragmentation 처리 안됨")
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
