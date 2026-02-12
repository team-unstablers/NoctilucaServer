//
//  RemoteChannelTests.swift
//  SiriusKitClientTests
//

import Testing
import Foundation

@testable import SiriusKitCore
@testable import SiriusKitClient

@Suite("Remote Channel Tests")
struct RemoteChannelTests {

    @Test("서버가 ChannelStartRequest를 보내면 채널이 생성된다")
    func remoteChannelStartRequestCreatesChannel() async throws {
        let harness = TestHarness()
        try await harness.startup()

        harness.client.shouldAcceptChannelCreation = true

        let remoteStream = MockStream()
        let channelID = UUID()

        // ChannelStartRequest를 미리 주입
        remoteStream.injectFrame(try FrameBuilder.channelStartRequestFrame(
            featureID: SiriusFeature.hidio.rawValue,
            channelID: channelID
        ))

        try await harness.transport.simulateRemoteStreamOpen(remoteStream)

        // ChannelStartResponse(success: true) 가 전송되어야 함
        let responseFrames = remoteStream.frames(withOpcode: .channelStartResponse)
        #expect(responseFrames.count == 1)

        let response = try remoteStream.decodeFirstMessage(
            withOpcode: .channelStartResponse, as: ChannelStartResponse.self
        )
        #expect(response?.success == true)

        // 채널이 등록되어야 함
        let channels = await harness.client.channelManager.channels
        #expect(channels[channelID] != nil)
    }

    @Test("shouldAcceptChannelCreation이 false면 스트림이 닫힌다")
    func rejectChannelWhenNotAccepting() async throws {
        let harness = TestHarness()
        try await harness.startup()

        // shouldAcceptChannelCreation 기본값은 false
        #expect(harness.client.shouldAcceptChannelCreation == false)

        let remoteStream = MockStream()
        try await harness.transport.simulateRemoteStreamOpen(remoteStream)

        // 스트림이 닫혀야 함
        #expect(remoteStream.isClosed)
    }

    @Test("지원하지 않는 feature의 ChannelStartRequest는 거부된다")
    func rejectUnsupportedFeatureRequest() async throws {
        let harness = TestHarness()
        // clipboard만 빼기
        harness.featureProvider.supportedFeatures = [.hidio, .projection]
        try await harness.startup()

        harness.client.shouldAcceptChannelCreation = true

        let remoteStream = MockStream()
        remoteStream.injectFrame(try FrameBuilder.channelStartRequestFrame(
            featureID: SiriusFeature.clipboard.rawValue,
            channelID: UUID()
        ))

        try await harness.transport.simulateRemoteStreamOpen(remoteStream)

        // ChannelStartResponse(success: false) 가 전송되어야 함
        let responseFrames = remoteStream.frames(withOpcode: .channelStartResponse)
        #expect(responseFrames.count == 1)

        let response = try remoteStream.decodeFirstMessage(
            withOpcode: .channelStartResponse, as: ChannelStartResponse.self
        )
        #expect(response?.success == false)
    }

    @Test("메인 채널이 없을 때 첫 리모트 스트림은 메인 채널이 된다")
    func firstRemoteStreamBecomesMainChannel() async throws {
        // startup()을 호출하지 않고 직접 channelManager를 사용
        let transport = MockClientRoleTransport()
        let featureProvider = MockFeatureProvider()
        let client = SiriusClient(transport: transport, featureProvider: featureProvider)

        // main channel이 없는 상태 확인
        let mainChannelBefore = await client.channelManager.mainChannel
        #expect(mainChannelBefore == nil)

        let remoteStream = MockStream()
        try await client.channelManager.handleStreamOpen(stream: remoteStream)

        let mainChannelAfter = await client.channelManager.mainChannel
        #expect(mainChannelAfter != nil)
    }
}
