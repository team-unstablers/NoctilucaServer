//
//  QUICServer.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/20/25.
//

import Foundation
import Network

struct SiriusQUICAlpn: RawRepresentable, Equatable, Hashable {
    typealias RawValue = String
    var rawValue: String
    
    init(rawValue: String) {
        self.rawValue = rawValue
    }
    
    static let siriusV1 = SiriusQUICAlpn(rawValue: "pl.unstabler.sirius")
}

enum QUICServerTransportError: Error {
    case identityLoadFailed
    case identitySanityCheckFailed
    case quicParametersCreationFailed
}

class QUICServerTransport: ServerTransport {
    private let port: NWEndpoint.Port
    private let identity: QUICServerIdentity
    
    private var listener: NWListener?
    
    private(set) var clients: [QUICClientTransport] = []
    
    init(port: NWEndpoint.Port, using identity: QUICServerIdentity) {
        self.port = port
        self.identity = identity
        
        super.init()
    }
    
    override func startup() async throws {
        let parameters = try await self.createQuicParameters()
        return try await withCheckedThrowingContinuation { continuation in
            
            
            do {
                let listener = try NWListener(using: parameters, on: port)
                listener.stateUpdateHandler = { newState in
                    switch newState {
                    case .ready:
                        continuation.resume()
                        self.delegate?.serverTransportDidStartListening(self)
                        return
                    case .failed(let error):
                        continuation.resume(throwing: error)
                        self.listener?.cancel()
                        return
                    case .cancelled:
                        self.delegate?.serverTransportDidStopListening(self)
                        break
                    default:
                        break
                    }
                }
                
                listener.newConnectionGroupHandler = { [weak self] connectionGroup in
                    print("New connection received from: \(connectionGroup.debugDescription))")
                    self?.handleNewConnectionGroup(connectionGroup: connectionGroup)
                }
                
                
                listener.start(queue: .main)
                self.listener = listener
            } catch {
                continuation.resume(throwing: error)
                return
            }
            
        }
    }
    
    override func shutdown() async throws {
        guard let listener = self.listener else {
            return
        }
        
        listener.cancel()
    
        self.listener = nil
    }
    
    private func handleNewConnectionGroup(connectionGroup: NWConnectionGroup) {
        let transport = QUICClientTransport(connectionGroup, serverTransport: self, id: ClientTransportIdentifier())
        
        self.registerClientTransport(transport)
    }
    
    internal func registerClientTransport(_ transport: QUICClientTransport) {
        transport.start()
        
        self.clients.append(transport)
        self.delegate?.serverTransportDidAcceptConnection(self, clientTransport: transport)
    }
    
    internal func unregisterClientTransport(_ transport: QUICClientTransport) {
        self.clients.removeAll { $0.id == transport.id }
    }
    
    
    // 개별 클라이언트 연결 처리
    private func startConnection(connection: NWConnection) {
        connection.start(queue: .main)
        receive(on: connection)
    }
    
    // 데이터 수신 및 에코(Echo) 전송
    private func receive(on connection: NWConnection) {
        // QUIC은 스트림 기반이지만, 여기서는 간단한 메시지 수신으로 처리
        connection.receiveMessage { [weak self] (data, context, isComplete, error) in
            if let error = error {
                print("Connection error: \(error)")
                connection.cancel()
                return
            }
            
            if let data = data, !data.isEmpty, let message = String(data: data, encoding: .utf8) {
                print("Received: \(message)")
                
                // 클라이언트에게 그대로 다시 전송 (Echo)
                self?.send(data: data, on: connection)
            }
            
            // 계속해서 다음 데이터를 수신 대기
            if isComplete {
                connection.cancel()
            } else {
                self?.receive(on: connection)
            }
        }
    }
    
    // 데이터 전송
    private func send(data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("Send error: \(error)")
            }
        })
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
            throw QUICServerTransportError.identitySanityCheckFailed
        }
        
        do {
            let secIdentity = try await self.identity.getServerIdentity()
            
            // TLS 옵션에 Identity 추가
            sec_protocol_options_set_local_identity(options.securityProtocolOptions, secIdentity)
        } catch {
            throw QUICServerTransportError.identityLoadFailed
        }
        
        // QUIC 파라미터 생성
        return NWParameters(quic: options)
    }
}

