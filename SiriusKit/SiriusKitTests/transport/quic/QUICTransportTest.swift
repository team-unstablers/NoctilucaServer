//
//  QUICTest.swift
//  SiriusKit
//
//  Created by Gyuhwan Park on 11/23/25.
//

import Foundation
import Testing

import Network

@testable import SiriusKit

/// QUIC 트랜스포트 관련한 클래스를 종합적으로 테스트합니다.
@Suite(.disabled(if: TestConfig.isUnattended))
final class QUICTransportTest {
    private let identifier: UUID
    private let port: NWEndpoint.Port
    
    private let serverIdentity: QUICServerIdentity
    
    init() async throws {
        self.identifier = UUID()
        self.port = NWEndpoint.Port(integerLiteral: 15495)
        
        let commonName = "pl.unstabler.sirius.SiriusKitTests.QUICtest.\(identifier.uuidString)"

        let identityArgs = QUICServerIdentityCreationArgs(
            identityLabel: commonName,
            commonName: commonName,
            organizationName: "team unstablers Inc.",
            organizationalUnitName: "SiriusKit",
            countryName: "KR",
            validityPeriodInDays: 1
        )
        
        self.serverIdentity = try InMemoryQUICServerIdentity.createSelfSignedIdentity(args: identityArgs)
        
        // ASSERTION: 호스트 자신이 신뢰 가능한 인증서를 사용해야만 함
        let sanityCheckResult = try await self.serverIdentity.sanityCheck()
        assert(sanityCheckResult, "this test requires a trustable server identity")
    }
    
    deinit {
        
    }
    
    
    // 심플 테스트 케이스
    @Test("QUIC 프로토콜의 서버가 정상적으로 기동되는가")
    func serverStartsSuccessfully() async throws {
        class TestServerDelegate: ServerTransportDelegate {
            var didStartListening = false
            
            func serverTransportDidStartListening(_ serverTransport: SiriusKit.ServerTransport) {
                didStartListening = true
            }
            
            func serverTransportDidStopListening(_ serverTransport: SiriusKit.ServerTransport) {
            }
            
            func serverTransportDidAcceptConnection(_ serverTransport: SiriusKit.ServerTransport, clientTransport: SiriusKit.ClientTransport) {
            }
            
            func serverTransportDidFailToAcceptConnection(_ serverTransport: SiriusKit.ServerTransport, error: any Error) {
            }
        }
        
        let delegate = TestServerDelegate()
        
        let server = QUICServerTransport(port: self.port, using: self.serverIdentity)
        server.delegate = delegate
        
        try await server.startup()
        defer {
            Task {
                do {
                    try await server.shutdown()
                } catch {
                    print("WARN: Failed to shutdown QUIC server transport: \(error)")
                }
            }
        }
        
        // condvar같은거 없나?
        try await Task.sleep(for: .seconds(1))
        
        #expect(delegate.didStartListening == true, "QUIC 서버가 정상적으로 기동되어야 합니다.")
    }
    
    /// SCENARIO:
    ///   1. QUIC 서버 트랜스포트를 기동한다.
    ///   2. 클라이언트가 서버에 연결을 시도한다.
    ///   3. 서버가 연결을 수락한다.
    ///   4. 클라이언트가 스트림을 연다.
    ///   5. 서버가 스트림을 수락한다.
    ///   6. 클라이언트가 ClientHello 메시지를 보낸다.
    ///   7. 서버가 ClientHello 메시지를 수신하고, ServerHello 메시지를 보낸다.
    ///   8. 서로의 메시지 수신을 assert() 한다.
    ///
    @Test("E2E 테스트 케이스 #1")
    func e2eTestCase_1() async throws {
        class TestClientTransportDelegate: ClientTransportDelegate {
            var error: (any Error)? = nil
            
            var didOpenStream = false
            var didReceiveData = false
            
            var streamListenerTask: Task<Void, any Error>? = nil
            var receivedData: Data? = nil
            
            func clientTransportDidOpenStream(_ transport: SiriusKit.ClientTransport, stream: SiriusKit.Stream) async throws {
                didOpenStream = true
                
                streamListenerTask = Task {
                    for await event in stream.events {
                        switch event {
                        case .data(let data):
                            self.didReceiveData = true
                            self.receivedData = data
                        case .closed:
                            break
                        case .error(let error):
                            self.error = error
                        }
                    }
                }
            }
            
            func clientTransportDidCloseStream(_ transport: SiriusKit.ClientTransport, stream: SiriusKit.Stream) async {
            }
            
            func clientTransportDidClose(_ transport: SiriusKit.ClientTransport, error: (any Error)?) async {
            }
        }
        
        class TestServerDelegate: ServerTransportDelegate {
            let transportDelegate: TestClientTransportDelegate
            
            var didStartListening = false
            var didAcceptConnection = false
            
            
            init(transportDelegate: TestClientTransportDelegate) {
                self.transportDelegate = transportDelegate
            }
            
            func serverTransportDidStartListening(_ serverTransport: SiriusKit.ServerTransport) {
                didStartListening = true
            }
            
            func serverTransportDidStopListening(_ serverTransport: SiriusKit.ServerTransport) {
            }
            
            func serverTransportDidAcceptConnection(_ serverTransport: SiriusKit.ServerTransport, clientTransport: SiriusKit.ClientTransport) {
                didAcceptConnection = true
                clientTransport.delegate = transportDelegate
            }
            
            func serverTransportDidFailToAcceptConnection(_ serverTransport: SiriusKit.ServerTransport, error: any Error) {
            }
        }
        
        let transportDelegate = TestClientTransportDelegate()
        let serverDelegate = TestServerDelegate(transportDelegate: transportDelegate)
        
        let server = QUICServerTransport(port: self.port, using: self.serverIdentity)
        server.delegate = serverDelegate
        
        try await server.startup()
        defer {
            Task {
                do {
                    try await server.shutdown()
                } catch {
                    print("WARN: Failed to shutdown QUIC server transport: \(error)")
                }
            }
        }
        
        // condvar같은거 없나?
        try await Task.sleep(for: .seconds(1))
        
        #expect(serverDelegate.didStartListening, "QUIC 서버가 정상적으로 기동되어야 합니다.")
        #expect(serverDelegate.didAcceptConnection, "QUIC 서버가 클라이언트의 연결을 수락해야 합니다.")
        
        #expect(transportDelegate.didOpenStream, "클라이언트가 스트림을 열어야 합니다.")
        #expect(transportDelegate.didReceiveData, "클라이언트가 서버로부터 데이터를 수신해야 합니다.")
        
        if let streamListenerTask = transportDelegate.streamListenerTask {
            streamListenerTask.cancel()
        }
    }
    
}
