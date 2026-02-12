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

        #expect(harness.transport.disconnectCalled)
    }
}
