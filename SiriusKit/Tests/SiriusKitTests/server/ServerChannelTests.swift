//
//  ServerChannelTests.swift
//  SiriusKitTests
//

import Testing
import Foundation

@testable import SiriusKitCore
@testable import SiriusKit

@Suite("Server Channel Tests")
struct ServerChannelTests {

    @Test("클라이언트의 ChannelStartRequest로 채널이 생성된다")
    func clientChannelStartRequestCreatesChannel() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let sessionHarness = await harness.simulateClientConnection()
        try await sessionHarness.openMainChannel()

        sessionHarness.session.shouldAcceptChannelCreation = true

        let channelStream = MockStream()
        let channelID = UUID()

        // ChannelStartRequest를 미리 주입
        channelStream.injectFrame(try FrameBuilder.channelStartRequestFrame(
            featureID: SiriusFeature.hidio.rawValue,
            channelID: channelID
        ))

        try await sessionHarness.clientTransport.simulateRemoteStreamOpen(channelStream)

        // ChannelStartResponse(success: true) 가 전송되어야 함
        let responseFrames = channelStream.frames(withOpcode: .channelStartResponse)
        #expect(responseFrames.count == 1)

        let response = try channelStream.decodeFirstMessage(
            withOpcode: .channelStartResponse, as: ChannelStartResponse.self
        )
        #expect(response?.success == true)

        // 채널이 등록되어야 함
        let channels = await sessionHarness.session.channelManager.channels
        #expect(channels[channelID] != nil)
    }

    @Test("shouldAcceptChannelCreation이 false면 채널 생성이 거부된다")
    func rejectChannelWhenNotAccepting() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let sessionHarness = await harness.simulateClientConnection()
        try await sessionHarness.openMainChannel()

        // shouldAcceptChannelCreation 기본값은 false
        #expect(sessionHarness.session.shouldAcceptChannelCreation == false)

        let channelStream = MockStream()
        try await sessionHarness.clientTransport.simulateRemoteStreamOpen(channelStream)

        // 스트림이 닫혀야 함
        #expect(channelStream.isClosed)
    }

    @Test("지원하지 않는 feature의 채널 요청은 거부된다")
    func rejectUnsupportedFeatureRequest() async throws {
        let harness = ServerTestHarness()
        // clipboard만 빼기
        harness.featureProvider.supportedFeatures = [.hidio, .projection]
        try await harness.startup()

        let sessionHarness = await harness.simulateClientConnection()
        try await sessionHarness.openMainChannel()

        sessionHarness.session.shouldAcceptChannelCreation = true

        let channelStream = MockStream()
        channelStream.injectFrame(try FrameBuilder.channelStartRequestFrame(
            featureID: SiriusFeature.clipboard.rawValue,
            channelID: UUID()
        ))

        try await sessionHarness.clientTransport.simulateRemoteStreamOpen(channelStream)

        // ChannelStartResponse(success: false) 가 전송되어야 함
        let responseFrames = channelStream.frames(withOpcode: .channelStartResponse)
        #expect(responseFrames.count == 1)

        let response = try channelStream.decodeFirstMessage(
            withOpcode: .channelStartResponse, as: ChannelStartResponse.self
        )
        #expect(response?.success == false)
    }

    @Test("서버가 openChannel()로 채널을 생성할 수 있다")
    func serverOpensChannel() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let sessionHarness = await harness.simulateClientConnection()
        try await sessionHarness.openMainChannel()

        let channelStream = MockStream()
        // ChannelStartResponse를 미리 주입
        channelStream.injectFrame(try FrameBuilder.channelStartResponseFrame(success: true))
        sessionHarness.clientTransport.enqueueMockStream(channelStream)

        let channelID = UUID()
        let channel = try await sessionHarness.session.channelManager.openChannel(
            for: .hidio,
            identifier: channelID,
            args: ["test"]
        )

        #expect(channel.identifier == channelID)
        #expect(channel.direction == .local)

        // ChannelStartRequest가 전송되었는지 확인
        let requestFrames = channelStream.frames(withOpcode: .channelStartRequest)
        #expect(requestFrames.count == 1)

        let request = try channelStream.decodeFirstMessage(
            withOpcode: .channelStartRequest, as: ChannelStartRequest.self
        )
        #expect(request?.featureID == SiriusFeature.hidio.rawValue)
        #expect(request?.channelID == channelID)
        #expect(request?.args == ["test"])
    }

    @Test("채널 열기 타임아웃")
    func channelOpenTimeout() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let sessionHarness = await harness.simulateClientConnection(channelOpenTimeout: 0.2)
        try await sessionHarness.openMainChannel()

        // 응답 없는 스트림
        let channelStream = MockStream()
        sessionHarness.clientTransport.enqueueMockStream(channelStream)

        await #expect(throws: ChannelManagerError.self) {
            try await sessionHarness.session.channelManager.openChannel(
                for: .hidio,
                identifier: UUID()
            )
        }
    }
}
