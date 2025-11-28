//
//  ClientRoleQUICTransport.swift
//  SiriusKit
//
//  Created by Coding Assistant on 03/01/25.
//

import Foundation
import Network
import Security

class ClientRoleQUICTransport: ClientRoleTransport {
    private let host: NWEndpoint.Host
    private let port: NWEndpoint.Port
    private let alpn: SiriusQUICAlpn
    
    private var connectionGroup: NWConnectionGroup?
    private(set) var streams: [StreamIdentifier: ClientRoleQUICStream] = [:]
    
    private let queue = DispatchQueue(label: "io.siriuskit.quic.client")
    private var mainStreamOpened = false
    
    private let verifyQueue = DispatchQueue(label: "io.siriuskit.quic.client.verify")
    
    init(host: NWEndpoint.Host, port: NWEndpoint.Port, alpn: SiriusQUICAlpn = .siriusV1) {
        self.host = host
        self.port = port
        self.alpn = alpn
        
        super.init()
    }
    
    override func connect() async throws {
        let parameters = try await self.createQuicParameters()
        
        let endpoint = NWEndpoint.hostPort(host: self.host, port: self.port)
        let descriptor = NWMultiplexGroup(to: endpoint)
        let connectionGroup = NWConnectionGroup(with: descriptor, using: parameters)
        self.connectionGroup = connectionGroup
        
        connectionGroup.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            
            switch state {
            case .ready:
                Task { await self.openMainStreamIfNeeded() }
            case .failed(let error):
                Task { await self.delegate?.clientTransport(self, didEncounterError: error) }
            case .cancelled:
                Task { await self.delegate?.clientTransportDidClose(self) }
            default:
                break
            }
        }
        
        connectionGroup.newConnectionHandler = { [weak self] connection in
            self?.handleIncomingConnection(connection)
        }
        
        connectionGroup.start(queue: self.queue)
    }
    
    override func disconnect() async throws {
        if let connectionGroup {
            connectionGroup.cancel()
            self.connectionGroup = nil
        }
        
        self.streams.removeAll()
        
        await self.delegate?.clientTransportDidClose(self)
    }
    
    override func openStream() async -> Result<Stream, ClientRoleTransportError> {
        guard let connectionGroup = self.connectionGroup else {
            return .failure(.connectionFailed(error: nil))
        }
        
        return await withCheckedContinuation { continuation in
            guard let connection = NWConnection(from: connectionGroup) else {
                continuation.resume(returning: .failure(.openStreamFailed(error: nil)))
                return
            }
            
            let stream = ClientRoleQUICStream(connection, transport: self)
            stream.setup { [weak self, weak stream] in
                guard let self, let stream else { return }
                
                self.registerStream(stream)
                continuation.resume(returning: .success(stream))
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
        self.streams.removeValue(forKey: stream.id)
    }
    
    private func handleIncomingConnection(_ connection: NWConnection) {
        let stream = ClientRoleQUICStream(connection, transport: self)
        
        stream.setup { [weak self] in
            guard let self else { return }
            self.registerStream(stream)
            
            Task {
                do {
                    try await self.delegate?.clientTransportDidOpenRemoteStream(self, stream: stream)
                } catch {
                    await self.delegate?.clientTransport(self, didEncounterError: error)
                }
            }
        }
        stream.start()
    }
    
    private func openMainStreamIfNeeded() async {
        guard self.mainStreamOpened == false else { return }
        self.mainStreamOpened = true
        
        let result = await self.openStream()
        switch result {
        case .success(let stream):
            do {
                try await self.delegate?.clientTransportDidOpenMainStream(self, stream: stream)
            } catch {
                self.mainStreamOpened = false
                await self.delegate?.clientTransport(self, didEncounterError: error)
            }
        case .failure(let error):
            self.mainStreamOpened = false
            await self.delegate?.clientTransport(self, didEncounterError: error)
        }
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
