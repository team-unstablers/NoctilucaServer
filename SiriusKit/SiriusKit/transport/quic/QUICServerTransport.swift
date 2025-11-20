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
    
    static let siriusV1 = SiriusQUICAlpn(rawValue: "pl.unstabler.sirius.v1")
}

class QUICServerTransport: ServerTransport {
    private let port: NWEndpoint.Port
    private var listener: NWListener?
    
    private(set) var clients: [QUICClientTransport] = []
    
    init(port: NWEndpoint.Port) {
        self.port = port
        
        
        super.init()
    }
    
    override func startup() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            guard let parameters = createQuicParameters() else {
                continuation.resume(throwing: ...)
                return
            }
            
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
                    print("New connection received from: \(String(describing: connectionGroup.endpoint))")
                    self?.handleNewConnectionGroup(connectionGroup: connectionGroup)
                }
                
                
                listener.start(queue: .main)
                self.listener = listener
            } catch {
                continuation.resume(throwing: ...)
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
    private func createQuicParameters() -> NWParameters? {
        // QUIC 보안 옵션 생성
        let options = NWProtocolQUIC.Options()
        
        // ALPN 설정 (클라이언트와 이 문자열이 일치해야 통신 가능)
        options.alpn = [SiriusQUICAlpn.siriusV1.rawValue]
        options.direction = .bidirectional
        
        // 보안 신원(Identity) 로드 - 실제 구현 시 .p12 파일 등에서 로드해야 함
        guard let identity = loadIdentity() else {
            print("Identity(Certificate) not found.")
            return nil
        }
        
        // TLS 옵션에 Identity 추가
        sec_protocol_options_set_local_identity(options.securityProtocolOptions, identity)
        
        // QUIC 파라미터 생성
        return NWParameters(quic: options)
    }
    
    // MARK: - 인증서 로드 헬퍼 (더미 함수)
    // 실제로는 Keychain이나 Bundle에 있는 .p12 파일을 읽어와야 합니다.
    private func loadIdentity() -> sec_identity_t? {
        // 주의: 실제 인증서 로딩 코드는 복잡하며 Keychain 접근이 필요할 수 있습니다.
        // 테스트를 위해 간단히 nil을 반환하지 않도록 구현해야 합니다.
        // 여기서는 예시를 위해 nil을 반환하지만, 실제로는 유효한 Identity가 있어야 서버가 시작됩니다.
        
        // 예: P12 파일에서 로드하는 로직 구현 필요
        return nil // 실제 사용시에는 유효한 sec_identity_t 객체를 리턴하세요.
    }
}

