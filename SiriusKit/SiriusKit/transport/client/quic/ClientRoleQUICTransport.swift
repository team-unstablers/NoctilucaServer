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
    
    private var connection: NWConnection?
    private(set) var streams: [StreamIdentifier: ClientRoleQUICStream] = [:]
    
    private let verifyQueue = DispatchQueue(label: "io.siriuskit.quic.client.verify")
    
    init(host: NWEndpoint.Host, port: NWEndpoint.Port, alpn: SiriusQUICAlpn = .siriusV1) {
        self.host = host
        self.port = port
        self.alpn = alpn
        
        super.init()
    }
    
    override func connect() async throws {
        let parameters = try await self.createQuicParameters()
        
        let connection = NWConnection(host: host, port: port, using: parameters)
        self.connection = connection
        
        let stream = ClientRoleQUICStream(connection, transport: self)
        stream.setup { [weak self, weak stream] in
            guard let self, let stream else { return }
            
            self.registerStream(stream)
            
            Task {
                do {
                    try await self.delegate?.clientTransportDidOpenMainStream(self, stream: stream)
                } catch {
                    await self.delegate?.clientTransport(self, didEncounterError: error)
                }
            }
        }
        stream.start()
    }
    
    override func disconnect() async throws {
        self.connection?.cancel()
        self.connection = nil
        self.streams.removeAll()
        
        await self.delegate?.clientTransportDidClose(self)
    }
    
    override func openStream() async -> Result<Stream, ClientRoleTransportError> {
        // TODO: QUIC 멀티 스트림 지원 추가
        guard let mainStream = self.streams.values.first else {
            return .failure(.openStreamFailed(error: nil))
        }
        
        return .success(mainStream)
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
                
                let identity = self.makeIdentityInfo(metadata: metadata)
                
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
    
    private func makeIdentityInfo(metadata: sec_protocol_metadata_t) -> ServerIdentityInfo {
        let certificateChain = (sec_protocol_metadata_copy_peer_certificate_chain(metadata) as? [SecCertificate]) ?? []
        let applicationLabel = try? certificateChain.first?.extractApplicationLabel()
        
        return ServerIdentityInfo(
            host: self.host.debugDescription,
            port: self.port.rawValue,
            alpn: self.alpn.rawValue,
            certificates: certificateChain,
            leafApplicationLabel: applicationLabel,
            notBefore: nil,
            notAfter: nil
        )
    }
}
