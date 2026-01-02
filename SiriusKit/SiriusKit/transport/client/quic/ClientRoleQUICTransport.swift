//
//  ClientRoleQUICTransport.swift
//  SiriusKit
//
//  Created by Coding Assistant on 03/01/25.
//

import Foundation
import Network
import Security

actor ClientRoleQUICTransport: ClientRoleTransport {
    nonisolated let id: ClientRoleTransportIdentifier = ClientRoleTransportIdentifier()
    nonisolated(unsafe) weak var delegate: ClientRoleTransportDelegate?
    
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let alpn: SiriusQUICAlpn
    
    private var connectionGroup: NWConnectionGroup?
    private var streams: [StreamIdentifier: ClientRoleQUICStream] = [:]
    
    private let queue = DispatchQueue(label: "io.siriuskit.quic.client")
    
    private let verifyQueue = DispatchQueue(label: "io.siriuskit.quic.client.verify")
    
    private var isFinalized: Bool = false
    
    init(host: NWEndpoint.Host, port: NWEndpoint.Port, alpn: SiriusQUICAlpn = .siriusV1) {
        self.host = host
        self.port = port
        self.alpn = alpn
    }
    
    func connect() async throws {
        let parameters = try await self.createQuicParameters()
        
        let endpoint = NWEndpoint.hostPort(host: self.host, port: self.port)
        let descriptor = NWMultiplexGroup(to: endpoint)
        let connectionGroup = NWConnectionGroup(with: descriptor, using: parameters)
        self.connectionGroup = connectionGroup
        
        connectionGroup.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            Task { await self.handleStateUpdate(state) }
        }
        
        connectionGroup.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            Task { await self.handleIncomingConnection(connection) }
        }
        
        connectionGroup.start(queue: self.queue)
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
        
        if let connectionGroup {
            connectionGroup.cancel()
            self.connectionGroup = nil
        }
        
        if let delegate {
            Task { await delegate.clientTransportDidClose(self) }
        }
    }
    
    func openStream() async -> Result<Stream, TransportLayerError> {
        guard let connectionGroup = self.connectionGroup else {
            return .failure(.connectionFailed(error: nil))
        }
        
        return await withCheckedContinuation { continuation in
            guard let connection = NWConnection(from: connectionGroup) else {
                continuation.resume(returning: .failure(.openStreamFailed(error: nil)))
                return
            }
            
            let stream = ClientRoleQUICStream(connection, transport: self, queue: self.queue)
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
    
    internal func registerStream(_ stream: ClientRoleQUICStream) {
        let streamId = stream.id
        guard !self.streams.keys.contains(streamId) else {
            return
        }
        
        self.streams.updateValue(stream, forKey: streamId)
    }
    
    internal func unregisterStream(_ stream: ClientRoleQUICStream) {
        guard self.streams.keys.contains(stream.id) else {
            return
        }
        
        self.streams.removeValue(forKey: stream.id)
    }
    
    private func handleStateUpdate(_ state: NWConnectionGroup.State) async {
        switch state {
        case .ready:
            if let delegate {
                Task { await delegate.clientTransportDidEstablishConnection(self) }
            }
        case .failed(let error):
            if let delegate {
                Task { await delegate.clientTransport(self, didEncounterError: error) }
            }
            await self.disconnect()
        case .cancelled:
            await self.disconnect()
        default:
            break
        }
    }
    
    private func handleIncomingConnection(_ connection: NWConnection) async {
        let stream = ClientRoleQUICStream(connection, transport: self, queue: self.queue)
        
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
    
    private func createQuicParameters() async throws -> NWParameters {
        let options = NWProtocolQUIC.Options()
        options.alpn = [self.alpn.rawValue]
        options.direction = .bidirectional
        
        sec_protocol_options_set_min_tls_protocol_version(
            options.securityProtocolOptions,
            tls_protocol_version_t.TLSv13
        )
        
        sec_protocol_options_set_verify_block(
            options.securityProtocolOptions,
            { [weak self] metadata, _, completion in
                guard let self else {
                    completion(false)
                    return
                }
                
                guard let identity = self.makeIdentityInfo(metadata: metadata) else {
                    completion(false)
                    return
                }
                
                DispatchQueue.main.async {
                    guard let delegate = self.delegate else {
                        completion(false)
                        return
                    }
                    
                    delegate.clientTransport(self, didReceiveServerIdentity: identity) { decision in
                        switch decision {
                        case .allow:
                            completion(true)
                        case .deny:
                            completion(false)
                        case .deferToApp:
                            completion(false)
                        }
                    }
                }
            },
            self.verifyQueue
        )
        
        return NWParameters(quic: options)
    }
    
    private func makeIdentityInfo(metadata: sec_protocol_metadata_t) -> ServerIdentityInfo? {
        var certificateChain: [SecCertificate] = []
        let result = sec_protocol_metadata_access_peer_certificate_chain(metadata) { certificateHandle in
            let secCertificate = sec_certificate_copy_ref(certificateHandle)
            certificateChain.append(secCertificate.takeRetainedValue())
        }
        
        guard result, !certificateChain.isEmpty else {
            return nil
        }
        
        let serverCertificate = certificateChain.first!
        
        let applicationLabel = try? serverCertificate.extractApplicationLabel()
        
        let notBefore = serverCertificate.extractNotBefore()
        let notAfter  = serverCertificate.extractNotAfter()
        
        return ServerIdentityInfo(
            host: self.host.debugDescription,
            port: self.port.rawValue,
            alpn: self.alpn.rawValue,
            certificates: certificateChain,
            leafApplicationLabel: applicationLabel,
            notBefore: notBefore,
            notAfter: notAfter
        )
    }
}
