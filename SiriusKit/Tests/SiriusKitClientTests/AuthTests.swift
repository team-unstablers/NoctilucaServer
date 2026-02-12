//
//  AuthTests.swift
//  SiriusKitClientTests
//

import Testing
import Foundation

@testable import SiriusKitCore
@testable import SiriusKitClient

@Suite("Auth Tests")
struct AuthTests {

    @Test("AuthChallenge를 수신하고 AuthRequest를 보낼 수 있다")
    func receiveAuthChallengeAndSendAuthRequest() async throws {
        let harness = TestHarness()
        try await harness.startup()

        let mainChannel = try #require(await harness.mainChannel)

        let nonce = Data([0xAA, 0xBB, 0xCC, 0xDD])
        let challengeFrame = try FrameBuilder.authChallengeFrame(
            acceptedMethods: ["password", "ssh-key"],
            nonce: nonce,
            message: "Please authenticate"
        )

        // AuthChallenge 이벤트 수신
        let eventTask = Task<MainChannelEvent, Error> {
            for await event in mainChannel.events {
                return event
            }
            throw CancellationError()
        }

        try await Task.sleep(for: .milliseconds(50))
        harness.mainChannelStream.injectFrame(challengeFrame)

        let event = try await eventTask.value
        guard case .receivedAuthChallenge(let challenge) = event else {
            Issue.record("Expected receivedAuthChallenge, got \(event)")
            return
        }

        #expect(challenge.acceptedMethods == ["password", "ssh-key"])
        #expect(challenge.nonce == nonce)
        #expect(challenge.message == "Please authenticate")

        // AuthRequest 전송
        let payload = Data([0x01, 0x02, 0x03])
        try await mainChannel.sendAuthRequest(AuthRequest(
            method: "password",
            nonce: nonce,
            payload: payload
        ))

        let requestFrames = harness.mainChannelStream.frames(withOpcode: .authRequest)
        #expect(requestFrames.count == 1)

        let sentRequest = try harness.mainChannelStream.decodeFirstMessage(
            withOpcode: .authRequest, as: AuthRequest.self
        )
        #expect(sentRequest?.method == "password")
        #expect(sentRequest?.nonce == nonce)
        #expect(sentRequest?.payload == payload)
    }

    @Test("AuthResponse 수신 시 세션 ID가 전달된다")
    func receiveAuthResponseWithSessionID() async throws {
        let harness = TestHarness()
        try await harness.startup()

        let mainChannel = try #require(await harness.mainChannel)

        let sessionID = UUID()
        let responseFrame = try FrameBuilder.authResponseFrame(sessionID: sessionID)

        let eventTask = Task<MainChannelEvent, Error> {
            for await event in mainChannel.events {
                return event
            }
            throw CancellationError()
        }

        try await Task.sleep(for: .milliseconds(50))
        harness.mainChannelStream.injectFrame(responseFrame)

        let event = try await eventTask.value
        guard case .receivedAuthResponse(let response) = event else {
            Issue.record("Expected receivedAuthResponse, got \(event)")
            return
        }

        #expect(response.sessionID == sessionID)
    }

    @Test("전체 핸드셰이크 + 인증 흐름이 정상 작동한다")
    func fullHandshakeAndAuthFlow() async throws {
        let harness = TestHarness()
        try await harness.startup()

        let mainChannel = try #require(await harness.mainChannel)

        // 1. ClientHello 전송
        try await mainChannel.sendClientHello(ClientHello(
            protocolVersion: .v1_0,
            agentName: "TestClient"
        ))

        // 2. ServerHello 수신
        let helloTask = Task<MainChannelEvent, Error> {
            for await event in mainChannel.events { return event }
            throw CancellationError()
        }
        try await Task.sleep(for: .milliseconds(50))
        harness.mainChannelStream.injectFrame(try FrameBuilder.serverHelloFrame(
            supportedFeatures: [SiriusFeature.hidio.rawValue]
        ))
        let helloEvent = try await helloTask.value
        guard case .receivedServerHello = helloEvent else {
            Issue.record("Expected receivedServerHello")
            return
        }

        // 3. AuthChallenge 수신
        let challengeTask = Task<MainChannelEvent, Error> {
            for await event in mainChannel.events { return event }
            throw CancellationError()
        }
        try await Task.sleep(for: .milliseconds(50))
        harness.mainChannelStream.injectFrame(try FrameBuilder.authChallengeFrame())
        let challengeEvent = try await challengeTask.value
        guard case .receivedAuthChallenge = challengeEvent else {
            Issue.record("Expected receivedAuthChallenge")
            return
        }

        // 4. AuthRequest 전송
        try await mainChannel.sendAuthRequest(AuthRequest(
            method: "password",
            nonce: Data([0x01, 0x02, 0x03, 0x04]),
            payload: Data("secret".utf8)
        ))

        // 5. AuthResponse 수신
        let sessionID = UUID()
        let authTask = Task<MainChannelEvent, Error> {
            for await event in mainChannel.events { return event }
            throw CancellationError()
        }
        try await Task.sleep(for: .milliseconds(50))
        harness.mainChannelStream.injectFrame(try FrameBuilder.authResponseFrame(sessionID: sessionID))
        let authEvent = try await authTask.value
        guard case .receivedAuthResponse(let response) = authEvent else {
            Issue.record("Expected receivedAuthResponse")
            return
        }

        #expect(response.sessionID == sessionID)

        // 전체 프레임 순서 확인
        let opcodes = harness.mainChannelStream.writtenFrames.map(\.opcode)
        #expect(opcodes == [.clientHello, .authRequest])
    }
}
