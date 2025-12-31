//
//  QUICServer.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation
import Network

enum ServerRoleQUICRootTransportError: Error {
    case identityLoadFailed
    case identitySanityCheckFailed
    case quicParametersCreationFailed
}

actor ServerRoleQUICRootTransport: ServerRoleRootTransport {
    private let port: NWEndpoint.Port
    private let identity: QUICServerIdentity
    
    private var _identity: SecIdentity?
    
    private var listener: NWListener?
    
    private(set) var clients: [ServerRoleQUICClientTransport] = []
    
    nonisolated(unsafe) weak var delegate: ServerRoleRootTransportDelegate?

    init(port: NWEndpoint.Port, using identity: QUICServerIdentity) {
        self.port = port
        self.identity = identity
    }
    
    func startup() async throws {
        let parameters = try await self.createQuicParameters()
        return try await withCheckedThrowingContinuation { continuation in
            
            
            do {
                let listener = try NWListener(using: parameters, on: port)
                listener.stateUpdateHandler = { newState in
                    Task {
                        switch newState {
                        case .ready:
                            continuation.resume()
                            self.delegate?.serverTransportDidStartListening(self)
                            return
                        case .failed(let error):
                            self.delegate?.serverTransport(self, didEncounterError: error)
                            continuation.resume(throwing: error)
                            await self.listener?.cancel()
                            return
                        case .cancelled:
                            self.delegate?.serverTransportDidStopListening(self)
                            break
                        default:
                            break
                        }
                    }
                }
                
                listener.newConnectionGroupHandler = { [weak self] connectionGroup in
                    Task {
                        print("New connection received from: \(connectionGroup.debugDescription))")
                        await self?.handleNewConnectionGroup(connectionGroup: connectionGroup)
                    }
                }
                
                
                listener.start(queue: .main)
                self.listener = listener
            } catch {
                continuation.resume(throwing: error)
                return
            }
            
        }
    }
    
    func shutdown() async throws {
        guard let listener = self.listener else {
            return
        }
        
        listener.cancel()
    
        self.listener = nil
    }
    
    private func handleNewConnectionGroup(connectionGroup: NWConnectionGroup) async {
        let transport = ServerRoleQUICClientTransport(connectionGroup, serverTransport: self, id: ServerRoleClientTransportIdentifier())
        
        await self.registerClientTransport(transport)
    }
    
    internal func registerClientTransport(_ transport: ServerRoleQUICClientTransport) async {
        await transport.setup()
        
        // HACK: QUICClientTransportDelegate를 설정할 타이밍을 제공하기 위해 여기서 델리게이트 콜백을 호출
        self.delegate?.serverTransportDidAcceptConnection(self, clientTransport: transport)

        await transport.start()
        
        self.clients.append(transport)
    }
    
    internal func unregisterClientTransport(_ transport: ServerRoleQUICClientTransport) async {
        self.clients.removeAll { $0.id == transport.id }
    }
    
    
    // QUIC 파라미터 및 TLS 설정 (가장 중요한 부분)
    private func createQuicParameters() async throws -> NWParameters {
        // QUIC 보안 옵션 생성
        let options = NWProtocolQUIC.Options()
        
        // ALPN 설정 (클라이언트와 이 문자열이 일치해야 통신 가능)
        options.alpn = [SiriusQUICAlpn.siriusV1.rawValue]
        options.direction = .bidirectional
        
        // 보안 신원(Identity) 로드 - 실제 구현 시 .p12 파일 등에서 로드해야 함
        guard try await self.identity.sanityCheck() else {
            throw ServerRoleQUICRootTransportError.identitySanityCheckFailed
        }
        
        do {
            let secIdentity = try await self.identity.getServerIdentity()
            
            // TLS 옵션에 Identity 추가
            sec_protocol_options_set_local_identity(options.securityProtocolOptions, secIdentity.asCHandle())
        } catch {
            throw ServerRoleQUICRootTransportError.identityLoadFailed
        }
        
        // QUIC 파라미터 생성
        return NWParameters(quic: options)
    }
}
