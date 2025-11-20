//
//  QUICClientTransport.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation
import Network

class QUICClientTransport: ClientTransport {
    let connectionGroup: NWConnectionGroup
    let serverTransport: QUICServerTransport
    
    private(set) var streams: [StreamIdentifier: QUICStream] = [:]
    
    private let _id: ClientTransportIdentifier
    
    override var id: ClientTransportIdentifier {
        _id
    }
    
    private(set) var error: Error?

    
    init(_ connectionGroup: NWConnectionGroup, serverTransport: QUICServerTransport, id: ClientTransportIdentifier) {
        self._id = id
        
        self.serverTransport = serverTransport
        self.connectionGroup = connectionGroup
    }
    
    override func disconnect() async throws {
        self.connectionGroup.cancel()
        
        self.serverTransport.unregisterClientTransport(self)
    }
    
    override func openStream() async -> Result<Stream, ClientTransportError> {
        guard let connection = NWConnection(from: self.connectionGroup) else {
            return .failure(...)
        }
        
        let stream = QUICStream(connection, transport: self)
        self.registerStream(stream)
        
        return .success(stream)
    }
    
    internal func start() {
        self.connectionGroup.stateUpdateHandler = { state in
            switch state {
            case .failed(let error):
                self.error = error
                Task {
                    try! await self.disconnect()
                }
            case .cancelled:
                self.delegate?.clientTransportDidClose(self, error: self.error)
                break
            default:
                break
            }
        }
        self.connectionGroup.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
        
        self.connectionGroup.start(queue: .main)
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        guard let streamId = connection.quicStreamIdentifier,
              !self.streams.keys.contains(streamId)
        else {
            return
        }
        
        let stream = QUICStream(connection, transport: self)
        self.registerStream(stream)
    }
    
    internal func registerStream(_ stream: QUICStream) {
        delegate?.clientTransportDidOpenStream(self, stream: stream)
        
        stream.setup()
        stream.start()
        
        self.streams.updateValue(stream, forKey: stream.id)
    }
    
    internal func unregisterStream(_ stream: QUICStream) {
        self.streams.removeValue(forKey: stream.id)
    }
}

extension QUICClientTransport: Hashable, Equatable, Identifiable {
    static func == (lhs: QUICClientTransport, rhs: QUICClientTransport) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
