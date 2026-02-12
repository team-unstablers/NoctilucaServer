//
//  ServerHandshakeTests.swift
//  SiriusKitTests
//

import Testing
import Foundation

@testable import SiriusKitCore
@testable import SiriusKit

@Suite("Server Handshake Tests")
struct ServerHandshakeTests {

    @Test("서버가 ClientHello를 수신한다")
    func receiveClientHello() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let sessionHarness = harness.simulateClientConnection()
        let (mainChannel, stream) = try await sessionHarness.openMainChannel()

        let clientHelloFrame = try FrameBuilder.clientHelloFrame(
            protocolVersion: .v1_0,
            agentName: "TestClient/1.0"
        )

        let eventTask = Task<MainChannelEvent, Error> {
            for await event in mainChannel.events {
                return event
            }
            throw CancellationError()
        }

        try await Task.sleep(for: .milliseconds(50))
        stream.injectFrame(clientHelloFrame)

        let event = try await eventTask.value
        guard case .receivedClientHello(let hello) = event else {
            Issue.record("Expected receivedClientHello, got \(event)")
            return
        }

        #expect(hello.protocolVersion == .v1_0)
        #expect(hello.agentName == "TestClient/1.0")
    }

    @Test("서버가 ServerHello를 전송한다")
    func sendServerHello() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let sessionHarness = harness.simulateClientConnection()
        let (mainChannel, stream) = try await sessionHarness.openMainChannel()

        let features = [
            SiriusFeature.hidio.rawValue,
            SiriusFeature.projection.rawValue,
        ]

        try await mainChannel.sendServerHello(ServerHello(
            protocolVersion: .v1_0,
            supportedFeatures: features,
            serverName: "TestServer/1.0",
            motd: "Welcome"
        ))

        let helloFrames = stream.frames(withOpcode: .serverHello)
        #expect(helloFrames.count == 1)

        let sentHello = try stream.decodeFirstMessage(
            withOpcode: .serverHello, as: ServerHello.self
        )
        #expect(sentHello?.protocolVersion == .v1_0)
        #expect(sentHello?.serverName == "TestServer/1.0")
        #expect(sentHello?.motd == "Welcome")
        #expect(sentHello?.supportedFeatures.count == 2)
    }

    @Test("서버가 ServerNotice를 전송한다")
    func sendServerNotice() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let sessionHarness = harness.simulateClientConnection()
        let (mainChannel, stream) = try await sessionHarness.openMainChannel()

        try await mainChannel.sendServerNotice(ServerNotice(
            severity: .fatal,
            code: 1,
            message: "Unsupported protocol version",
            timestamp: 1234567890
        ))

        let noticeFrames = stream.frames(withOpcode: .serverNotice)
        #expect(noticeFrames.count == 1)

        let sentNotice = try stream.decodeFirstMessage(
            withOpcode: .serverNotice, as: ServerNotice.self
        )
        #expect(sentNotice?.severity == .fatal)
        #expect(sentNotice?.code == 1)
        #expect(sentNotice?.message == "Unsupported protocol version")
        #expect(sentNotice?.timestamp == 1234567890)
    }
}
