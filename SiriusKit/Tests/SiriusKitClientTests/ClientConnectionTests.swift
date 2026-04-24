//
//  ClientConnectionTests.swift
//  SiriusKitClientTests
//

import Testing
import Foundation

@testable import SiriusKitCore
@testable import SiriusKitClient

@Suite("Client Connection Tests")
struct ClientConnectionTests {

    @Test("startup()이 transport.connect()를 호출한다")
    func startupCallsConnect() async throws {
        let harness = TestHarness()
        try await harness.startup()

        #expect(harness.transport.connectCalled)
    }

    @Test("connect 성공 후 메인 채널이 생성된다")
    func mainChannelCreatedAfterConnect() async throws {
        let harness = TestHarness()
        try await harness.startup()

        let mainChannel = await harness.mainChannel
        #expect(mainChannel != nil)
    }

    @Test("connect 성공 후 delegate.didCreateMainChannel이 호출된다")
    func delegateCalledAfterMainChannelCreation() async throws {
        let harness = TestHarness()
        try await harness.startup()

        #expect(harness.delegate.mainChannel != nil)
    }

    @Test("shutdown()이 transport.disconnect()를 호출한다")
    func shutdownCallsDisconnect() async throws {
        let harness = TestHarness()
        try await harness.startup()

        await harness.client.shutdown()

        // SiriusClient.shutdown()는 transport.disconnect()를 `Task.detached { ... }`로
        // 분리 호출한다. 실제 호출이 반영될 때까지 짧게 대기한다.
        let deadline = Date().addingTimeInterval(2)
        while !harness.transport.disconnectCalled {
            if Date() > deadline { break }
            try? await Task.sleep(for: .milliseconds(5))
        }

        #expect(harness.transport.disconnectCalled)
    }
}
