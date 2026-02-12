//
//  HandshakeTests.swift
//  SiriusKitClientTests
//

import Testing
import Foundation

@testable import SiriusKitCore
@testable import SiriusKitClient

@Suite("Handshake Tests")
struct HandshakeTests {

    @Test("ClientHello를 보내고 ServerHello를 수신한다")
    func sendClientHelloAndReceiveServerHello() async throws {
        let harness = TestHarness()
        try await harness.startup()

        let mainChannel = try #require(await harness.mainChannel)

        // ClientHello 전송
        try await mainChannel.sendClientHello(ClientHello(
            protocolVersion: .v1_0,
            agentName: "TestClient/1.0"
        ))

        // 전송된 프레임 확인
        let clientHelloFrames = harness.mainChannelStream.frames(withOpcode: .clientHello)
        #expect(clientHelloFrames.count == 1)

        let sentHello = try harness.mainChannelStream.decodeFirstMessage(
            withOpcode: .clientHello, as: ClientHello.self
        )
        #expect(sentHello?.protocolVersion == .v1_0)
        #expect(sentHello?.agentName == "TestClient/1.0")

        // ServerHello 주입
        let serverHelloFrame = try FrameBuilder.serverHelloFrame(
            supportedFeatures: [SiriusFeature.hidio.rawValue, SiriusFeature.projection.rawValue],
            serverName: "TestServer/1.0"
        )

        // 이벤트 수신 Task 시작
        let eventTask = Task<MainChannelEvent, Error> {
            for await event in mainChannel.events {
                return event
            }
            throw CancellationError()
        }

        // 딜레이 후 프레임 주입
        try await Task.sleep(for: .milliseconds(50))
        harness.mainChannelStream.injectFrame(serverHelloFrame)

        let event = try await eventTask.value
        guard case .receivedServerHello(let hello) = event else {
            Issue.record("Expected receivedServerHello, got \(event)")
            return
        }

        #expect(hello.protocolVersion == .v1_0)
        #expect(hello.serverName == "TestServer/1.0")
    }

    @Test("ServerNotice(fatal)를 수신하면 이벤트로 전달된다")
    func receiveServerNoticeFatal() async throws {
        let harness = TestHarness()
        try await harness.startup()

        let mainChannel = try #require(await harness.mainChannel)

        let noticeFrame = try FrameBuilder.serverNoticeFrame(
            severity: .fatal,
            code: 1,
            message: "Protocol error"
        )

        let eventTask = Task<MainChannelEvent, Error> {
            for await event in mainChannel.events {
                return event
            }
            throw CancellationError()
        }

        try await Task.sleep(for: .milliseconds(50))
        harness.mainChannelStream.injectFrame(noticeFrame)

        let event = try await eventTask.value
        guard case .receivedServerNotice(let notice) = event else {
            Issue.record("Expected receivedServerNotice, got \(event)")
            return
        }

        #expect(notice.severity == .fatal)
        #expect(notice.code == 1)
        #expect(notice.message == "Protocol error")
    }

    @Test("ServerHello의 supportedFeatures가 올바르게 파싱된다")
    func serverHelloSupportedFeaturesAreParsed() async throws {
        let harness = TestHarness()
        try await harness.startup()

        let mainChannel = try #require(await harness.mainChannel)

        let features = [
            SiriusFeature.hidio.rawValue,
            SiriusFeature.projection.rawValue,
            SiriusFeature.projectionData.rawValue,
        ]
        let serverHelloFrame = try FrameBuilder.serverHelloFrame(supportedFeatures: features)

        let eventTask = Task<MainChannelEvent, Error> {
            for await event in mainChannel.events {
                return event
            }
            throw CancellationError()
        }

        try await Task.sleep(for: .milliseconds(50))
        harness.mainChannelStream.injectFrame(serverHelloFrame)

        let event = try await eventTask.value
        guard case .receivedServerHello(let hello) = event else {
            Issue.record("Expected receivedServerHello, got \(event)")
            return
        }

        #expect(hello.supportedFeatures.count == 3)
        #expect(hello.supportedFeatures.contains(SiriusFeature.hidio.rawValue))
        #expect(hello.supportedFeatures.contains(SiriusFeature.projection.rawValue))
        #expect(hello.supportedFeatures.contains(SiriusFeature.projectionData.rawValue))
    }
}
