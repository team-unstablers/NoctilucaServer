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

class ServerRoleQUICClientTransport: ServerRoleClientTransport {
    let connectionGroup: NWConnectionGroup
    let serverTransport: ServerRoleQUICRootTransport
    
    private(set) var streams: [StreamIdentifier: ServerRoleQUICStream] = [:]
    
    private let _id: ServerRoleClientTransportIdentifier
    
    override var id: ServerRoleClientTransportIdentifier {
        _id
    }
    
    
    init(_ connectionGroup: NWConnectionGroup, serverTransport: ServerRoleQUICRootTransport, id: ServerRoleClientTransportIdentifier) {
        self._id = id
        
        self.serverTransport = serverTransport
        self.connectionGroup = connectionGroup
    }
    
    override func disconnect() async throws {
        self.connectionGroup.cancel()
        
        self.serverTransport.unregisterClientTransport(self)
    }
    
    override func openStream() async -> Result<Stream, ServerRoleClientTransportError> {
        guard let connection = NWConnection(from: self.connectionGroup) else {
            return .failure(.openStreamFailed(error: nil))
        }
        
        let stream = ServerRoleQUICStream(connection, transport: self)
        self.registerStream(stream)
        
        return .success(stream)
    }
    
    internal func setup() {
        self.connectionGroup.stateUpdateHandler = { state in
            switch state {
            case .failed(let error):
                Task {
                    await self.delegate?.clientTransport(self, didEncounterError: error)
                    try? await self.disconnect()
                }
            case .cancelled:
                Task {
                    await self.delegate?.clientTransportDidClose(self)
                }
            default:
                break
            }
        }
        self.connectionGroup.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
    }
    
    internal func start() {
        self.connectionGroup.start(queue: .main)
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        let stream = ServerRoleQUICStream(connection, transport: self)
        
        stream.setup { [weak self] in
            guard let _self = self else { return }
            
            _self.registerStream(stream)
            
            Task {
                do {
                    try await _self.delegate?.clientTransportDidOpenRemoteStream(_self, stream: stream)
                } catch {
                    await _self.delegate?.clientTransport(_self, didEncounterError: error)
                }
            }
        }
        stream.start()
    }
    
    internal func registerStream(_ stream: ServerRoleQUICStream) {
        // FIXME: ready가 아닌 상태에서 stream.id 액세스하면 맛감
        assert(stream.connection.state == .ready)
        
        let streamId = stream.id
        guard !self.streams.keys.contains(streamId) else {
            return
        }

                
        self.streams.updateValue(stream, forKey: streamId)
    }
    
    internal func unregisterStream(_ stream: ServerRoleQUICStream) {
        self.streams.removeValue(forKey: stream.id)
    }
}

extension ServerRoleQUICClientTransport: Hashable, Equatable, Identifiable {
    static func == (lhs: ServerRoleQUICClientTransport, rhs: ServerRoleQUICClientTransport) -> Bool {
        return lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
