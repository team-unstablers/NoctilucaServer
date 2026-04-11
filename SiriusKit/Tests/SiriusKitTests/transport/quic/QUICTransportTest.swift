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
@Suite(.disabled("자가 서명 인증서 신뢰 처리에 사용자 인증 다이얼로그가 필요"))
final class QUICTransportTest {
    private let identifier: UUID
    private let port: NWEndpoint.Port
    
    private let serverIdentity: QUICServerIdentity
    
    init() async throws {
        self.identifier = UUID()
        self.port = NWEndpoint.Port(integerLiteral: 15495)
        
        let commonName = "so.libsirius.SiriusKit.tests.QUICtest.\(identifier.uuidString)"

        let identityArgs = QUICServerIdentityCreationArgs(
            identityLabel: commonName,
            commonName: commonName,
            organizationName: "team unstablers Inc.",
            organizationalUnitName: "SiriusKit",
            countryName: "KR",
            validityPeriodInDays: 1
        )
        
        self.serverIdentity = try KeychainQUICServerIdentity.createSelfSignedIdentity(args: identityArgs)
        
        // ASSERTION: 호스트 자신이 신뢰 가능한 인증서를 사용해야만 함
        let sanityCheckResult = try await self.serverIdentity.sanityCheck()
        assert(sanityCheckResult, "this test requires a trustable server identity")
    }
    
    deinit {
        
    }
    
    
    // 심플 테스트 케이스
    @Test("QUIC 프로토콜의 서버가 정상적으로 기동되는가")
    func serverStartsSuccessfully() async throws {
        class TestServerDelegate: ServerRoleRootTransportDelegate {
            func serverTransport(_ serverTransport: any SiriusKit.ServerRoleRootTransport, didEncounterError error: any Error) {
                
            }
            
            var didStartListening = false
            
            func serverTransportDidStartListening(_ serverTransport: SiriusKit.ServerRoleRootTransport) {
                didStartListening = true
            }
            
            func serverTransportDidStopListening(_ serverTransport: SiriusKit.ServerRoleRootTransport) {
            }
            
            func serverTransportDidAcceptConnection(_ serverTransport: SiriusKit.ServerRoleRootTransport, clientTransport: SiriusKit.ServerRoleClientTransport) {
            }
            
            func serverTransportDidFailToAcceptConnection(_ serverTransport: SiriusKit.ServerRoleRootTransport, error: any Error) {
            }
        }
        
        let delegate = TestServerDelegate()
        
        let server = ServerRoleQUICRootTransport(port: self.port, using: self.serverIdentity)
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
    ///   2. 심플 QUIC 클라이언트가 서버에 연결을 시도한다.
    ///   3. 서버가 연결을 수락하고, 클라이언트는 메인 스트림 준비 이벤트를 수신한다.
    ///   4. 클라이언트가 프레임을 전송하면 서버(ClientTransportDelegate)가 수신한다.
    ///   5. 서버가 프레임을 전송하면 클라이언트가 수신한다.
    @Test("E2E 테스트 케이스 #1")
    func e2eTestCase_1() async throws {
        final class TestClientTransportDelegate: ServerRoleClientTransportDelegate, @unchecked Sendable {
            var didOpenStream = false
            var didReceiveFrameFromClient = false
            var receivedFrameFromClient: SiriusFrame?
            var error: (any Error)?

            var openedStream: SiriusKit.Stream?
            var streamListenerTask: Task<Void, Never>?
            
            func clientTransportDidOpenRemoteStream(_ transport: SiriusKit.ServerRoleClientTransport, stream: SiriusKit.Stream) async throws {
                print("didOpenStream called")
                didOpenStream = true
                openedStream = stream
                
                streamListenerTask = Task {
                    for await event in stream.events {
                        switch event {
                        case .frame(let frame):
                            if frame.isValid() {
                                self.receivedFrameFromClient = frame
                                self.didReceiveFrameFromClient = true
                            }
                        case .error(let error):
                            self.error = error
                        case .closed:
                            break
                        }
                    }
                }
            }
            
            func clientTransportDidCloseStream(_ transport: SiriusKit.ServerRoleClientTransport, stream: SiriusKit.Stream) async {
            }
            
            func clientTransportDidClose(_ transport: SiriusKit.ServerRoleClientTransport) async {
            }
            
            func clientTransport(_ transport: SiriusKit.ServerRoleClientTransport, didEncounterError error: any Error) async {
                self.error = error
            }
        }
        
        final class TestServerDelegate: ServerRoleRootTransportDelegate, @unchecked Sendable {
            let transportDelegate: TestClientTransportDelegate
            var didStartListening = false
            var didAcceptConnection = false
            
            init(transportDelegate: TestClientTransportDelegate) {
                self.transportDelegate = transportDelegate
            }
            
            func serverTransportDidStartListening(_ serverTransport: SiriusKit.ServerRoleRootTransport) {
                didStartListening = true
            }
            
            func serverTransportDidStopListening(_ serverTransport: SiriusKit.ServerRoleRootTransport) {
            }
            
            func serverTransport(_ serverTransport: SiriusKit.ServerRoleRootTransport, didEncounterError error: any Error) {
            }
            
            func serverTransportDidAcceptConnection(_ serverTransport: SiriusKit.ServerRoleRootTransport, clientTransport: SiriusKit.ServerRoleClientTransport) {
                didAcceptConnection = true
                clientTransport.delegate = transportDelegate
            }
            
            func serverTransportDidFailToAcceptConnection(_ serverTransport: SiriusKit.ServerRoleRootTransport, error: any Error) {
            }
        }
        
        let transportDelegate = TestClientTransportDelegate()
        let serverDelegate = TestServerDelegate(transportDelegate: transportDelegate)
        
        let server = ServerRoleQUICRootTransport(port: self.port, using: self.serverIdentity)
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
        
        // 서버가 준비될 때까지 대기
        try await Task.sleep(for: .seconds(1))
        #expect(serverDelegate.didStartListening, "QUIC 서버가 정상적으로 기동되어야 합니다.")
        
        // 클라이언트가 서버에 연결 시도
        let client = SimpleQUICClient(host: "127.0.0.1", port: self.port.rawValue)
        await client.connect()
        
        // 클라이언트 이벤트를 일부 소비하여 연결 상태를 확인
        var didReceiveConnectedEvent = false
        var didReceiveMainStreamOpenEvent = false
        var clientError: (any Error)?
        
        let iteratorBox = AsyncIteratorBox(client.events.makeAsyncIterator())
        func nextClientEvent(timeout: Duration = .seconds(3)) async -> SimpleQUICClientEvent? {
            await withTaskGroup(of: SimpleQUICClientEvent?.self) { group in
                group.addTask {
                    await iteratorBox.next()
                }
                group.addTask {
                    try? await Task.sleep(for: timeout)
                    return nil
                }

                let event = await group.next()!
                group.cancelAll()
                return event
            }
        }
        
        for _ in 0..<4 {
            guard let event = await nextClientEvent() else { break }
            
            switch event {
            case .connected:
                didReceiveConnectedEvent = true
            case .mainStreamOpen:
                didReceiveMainStreamOpenEvent = true
            case .error(let error):
                clientError = error
            default:
                break
            }
            
            if didReceiveConnectedEvent && didReceiveMainStreamOpenEvent {
                break
            }
        }
        
        // 서버가 연결을 인지할 시간을 잠시 준다.
        try await Task.sleep(for: .seconds(1))
        
        #expect(clientError == nil, "클라이언트는 오류 없이 연결되어야 합니다.")
        #expect(didReceiveConnectedEvent == true, "클라이언트 연결 이벤트가 발생해야 합니다.")
        #expect(didReceiveMainStreamOpenEvent == true, "클라이언트는 메인 스트림 오픈 이벤트를 수신해야 합니다.")
        #expect(serverDelegate.didAcceptConnection == true, "서버가 클라이언트의 연결을 수락해야 합니다.")
        
        // 4. 클라이언트 -> 서버로 프레임 전송
        let clientPayload = Data("hello-from-client".utf8)
        let clientOpcode = MessageOpcode(rawValue: 0xAA01)
        let clientFrame = SiriusFrame(opcode: clientOpcode, length: UInt32(clientPayload.count), data: clientPayload)
        
        await client.send(clientFrame)
        try await Task.sleep(for: .milliseconds(500))
        
        #expect(transportDelegate.didOpenStream == true, "서버 측 클라이언트 트랜스포트가 스트림을 열어야 합니다.")
        #expect(transportDelegate.error == nil, "서버 측 스트림에서 에러가 발생하지 않아야 합니다.")
        #expect(transportDelegate.didReceiveFrameFromClient == true, "서버는 클라이언트가 보낸 프레임을 수신해야 합니다.")
        if let received = transportDelegate.receivedFrameFromClient {
            #expect(received.opcode == clientOpcode, "서버에서 수신한 opcode가 전송한 opcode와 일치해야 합니다.")
            #expect(received.data == clientPayload, "서버에서 수신한 페이로드가 전송한 페이로드와 일치해야 합니다.")
        }
        
        // 5. 서버 -> 클라이언트로 프레임 전송
        let serverPayload = Data("hello-from-server".utf8)
        let serverOpcode = MessageOpcode(rawValue: 0xBB01)
        if let stream = transportDelegate.openedStream {
            let writeResult = await stream.write(frame: serverPayload, opcode: serverOpcode)
            if case .failure(let error) = writeResult {
                #expect(Bool(false), "서버가 프레임을 전송할 수 있어야 합니다. 에러: \(error)")
            }
        } else {
            #expect(Bool(false), "서버가 전송할 스트림을 확보해야 합니다.")
        }
        
        func recvWithTimeout(timeout: Duration = .seconds(3)) async -> SiriusFrame? {
            await withTaskGroup(of: SiriusFrame?.self) { group in
                group.addTask {
                    await client.recv()
                }
                group.addTask {
                    try? await Task.sleep(for: timeout)
                    return nil
                }
                
                let frame = await group.next()!
                group.cancelAll()
                return frame
            }
        }
        
        let receivedByClient = await recvWithTimeout()
        #expect(receivedByClient != nil, "클라이언트는 서버가 보낸 프레임을 수신해야 합니다.")
        if let frame = receivedByClient {
            #expect(frame.opcode == serverOpcode, "클라이언트가 수신한 opcode가 서버가 전송한 opcode와 일치해야 합니다.")
            #expect(frame.data == serverPayload, "클라이언트가 수신한 페이로드가 서버가 전송한 페이로드와 일치해야 합니다.")
        }
        
        // 정리: 스트림 리스너 태스크 중단
        if let streamListenerTask = transportDelegate.streamListenerTask {
            streamListenerTask.cancel()
        }
    }

}

/// 테스트 내부에서 AsyncIterator 를 @Sendable 컨텍스트로 넘기기 위한 얇은 박스.
private final class AsyncIteratorBox<Iter: AsyncIteratorProtocol>: @unchecked Sendable
where Iter.Element: Sendable {
    private var iterator: Iter

    init(_ iterator: Iter) {
        self.iterator = iterator
    }

    func next() async -> Iter.Element? {
        try? await iterator.next()
    }
}
