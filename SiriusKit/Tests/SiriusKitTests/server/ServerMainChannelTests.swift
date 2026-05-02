//
//  ServerMainChannelTests.swift
//  SiriusKitTests
//

import Testing
import Foundation

@testable import SiriusKitCore
@testable import SiriusKit

@Suite("Server Main Channel Tests")
struct ServerMainChannelTests {

    @Test("첫 번째 스트림이 메인 채널이 된다")
    func firstStreamBecomesMainChannel() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let sessionHarness = await harness.simulateClientConnection()

        let mainChannelBefore = await sessionHarness.session.channelManager.mainChannel
        #expect(mainChannelBefore == nil)

        try await sessionHarness.openMainChannel()

        let mainChannelAfter = await sessionHarness.session.channelManager.mainChannel
        #expect(mainChannelAfter != nil)
    }

    @Test("메인 채널 생성 시 delegate.clientSessionDidCreateMainChannel이 호출된다")
    func delegateNotifiedOnMainChannelCreation() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let sessionHarness = await harness.simulateClientConnection()

        #expect(sessionHarness.sessionDelegate.mainChannel == nil)

        try await sessionHarness.openMainChannel()

        #expect(sessionHarness.sessionDelegate.mainChannel != nil)
    }

    @Test("shouldAcceptChannelCreation이 false이면 두 번째 스트림이 닫힌다")
    func secondStreamClosedWhenNotAccepting() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let sessionHarness = await harness.simulateClientConnection()
        try await sessionHarness.openMainChannel()

        // shouldAcceptChannelCreation 기본값은 false
        #expect(sessionHarness.session.shouldAcceptChannelCreation == false)

        let secondStream = MockStream()
        try await sessionHarness.clientTransport.simulateRemoteStreamOpen(secondStream)

        #expect(secondStream.isClosed)
    }
}
