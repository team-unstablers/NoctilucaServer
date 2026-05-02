//
//  ServerAuthTests.swift
//  SiriusKitTests
//

import Testing
import Foundation

@testable import SiriusKitCore
@testable import SiriusKit

@Suite("Server Auth Tests")
struct ServerAuthTests {

    @Test("서버가 AuthChallenge를 전송하고 AuthRequest를 수신한다")
    func sendAuthChallengeAndReceiveAuthRequest() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let sessionHarness = await harness.simulateClientConnection()
        let (mainChannel, stream) = try await sessionHarness.openMainChannel()

        // 1. AuthChallenge 전송
        let nonce = Data([0xAA, 0xBB, 0xCC, 0xDD])
        try await mainChannel.sendAuthChallenge(AuthChallenge(
            acceptedMethods: ["password", "ssh-key"],
            nonce: nonce,
            message: "Please authenticate"
        ))

        let challengeFrames = stream.frames(withOpcode: .authChallenge)
        #expect(challengeFrames.count == 1)

        let sentChallenge = try stream.decodeFirstMessage(
            withOpcode: .authChallenge, as: AuthChallenge.self
        )
        #expect(sentChallenge?.acceptedMethods == ["password", "ssh-key"])
        #expect(sentChallenge?.nonce == nonce)

        // 2. AuthRequest 수신
        let payload = Data([0x01, 0x02, 0x03])
        let authRequestFrame = try FrameBuilder.authRequestFrame(
            method: "password",
            nonce: nonce,
            payload: payload
        )

        let eventTask = Task<MainChannelEvent, Error> {
            for await event in mainChannel.events {
                return event
            }
            throw CancellationError()
        }

        try await Task.sleep(for: .milliseconds(50))
        stream.injectFrame(authRequestFrame)

        let event = try await eventTask.value
        guard case .receivedAuthRequest(let request) = event else {
            Issue.record("Expected receivedAuthRequest, got \(event)")
            return
        }

        #expect(request.method == "password")
        #expect(request.nonce == nonce)
        #expect(request.payload == payload)
    }

    @Test("서버가 AuthResponse를 전송하고 세션 ID가 올바르다")
    func sendAuthResponse() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let sessionHarness = await harness.simulateClientConnection()
        let (mainChannel, stream) = try await sessionHarness.openMainChannel()

        let sessionID = UUID()
        try await mainChannel.sendAuthResponse(AuthResponse(sessionID: sessionID))

        let responseFrames = stream.frames(withOpcode: .authResponse)
        #expect(responseFrames.count == 1)

        let sentResponse = try stream.decodeFirstMessage(
            withOpcode: .authResponse, as: AuthResponse.self
        )
        #expect(sentResponse?.sessionID == sessionID)
    }

    @Test("전체 서버 핸드셰이크 + 인증 흐름이 정상 작동한다")
    func fullServerHandshakeAndAuthFlow() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let sessionHarness = await harness.simulateClientConnection()
        let (mainChannel, stream) = try await sessionHarness.openMainChannel()

        // 1. ClientHello 수신
        let helloTask = Task<MainChannelEvent, Error> {
            for await event in mainChannel.events { return event }
            throw CancellationError()
        }
        try await Task.sleep(for: .milliseconds(50))
        stream.injectFrame(try FrameBuilder.clientHelloFrame(agentName: "TestClient"))
        let helloEvent = try await helloTask.value
        guard case .receivedClientHello(let hello) = helloEvent else {
            Issue.record("Expected receivedClientHello")
            return
        }
        #expect(hello.agentName == "TestClient")

        // 2. ServerHello 전송
        try await mainChannel.sendServerHello(ServerHello(
            protocolVersion: .v1_0,
            supportedFeatures: [SiriusFeature.hidio.rawValue],
            serverName: "TestServer",
            motd: nil
        ))

        // 3. AuthChallenge 전송
        let nonce = Data([0x01, 0x02, 0x03, 0x04])
        try await mainChannel.sendAuthChallenge(AuthChallenge(
            acceptedMethods: ["password"],
            nonce: nonce,
            message: nil
        ))

        // 4. AuthRequest 수신
        let authTask = Task<MainChannelEvent, Error> {
            for await event in mainChannel.events { return event }
            throw CancellationError()
        }
        try await Task.sleep(for: .milliseconds(50))
        stream.injectFrame(try FrameBuilder.authRequestFrame(
            method: "password",
            nonce: nonce,
            payload: Data("secret".utf8)
        ))
        let authEvent = try await authTask.value
        guard case .receivedAuthRequest(let request) = authEvent else {
            Issue.record("Expected receivedAuthRequest")
            return
        }
        #expect(request.method == "password")

        // 5. AuthResponse 전송
        let sessionID = UUID()
        try await mainChannel.sendAuthResponse(AuthResponse(sessionID: sessionID))

        // 전체 프레임 순서 확인 (서버가 전송한 프레임)
        let opcodes = stream.writtenFrames.map(\.opcode)
        #expect(opcodes == [.serverHello, .authChallenge, .authResponse])
    }
}
