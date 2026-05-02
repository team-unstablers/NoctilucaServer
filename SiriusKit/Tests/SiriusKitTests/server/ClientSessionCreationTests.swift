//
//  ClientSessionCreationTests.swift
//  SiriusKitTests
//

import Testing
import Foundation

@testable import SiriusKitCore
@testable import SiriusKit

@Suite("Client Session Creation Tests")
struct ClientSessionCreationTests {

    @Test("클라이언트 연결 시 ClientSession이 생성된다")
    func clientConnectionCreatesSession() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        await harness.simulateClientConnection()

        #expect(await harness.server.sessions.count == 1)
    }

    @Test("delegate.siriusServerDidAcceptClientSession이 호출된다")
    func delegateNotifiedOnSessionCreation() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        await harness.simulateClientConnection()

        #expect(harness.serverDelegate.acceptedSessions.count == 1)
    }

    @Test("ClientSession의 remoteAddress가 올바르게 설정된다")
    func sessionHasCorrectRemoteAddress() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let sessionHarness = await harness.simulateClientConnection()

        #expect(sessionHarness.session.remoteEndpoint?.address.description == "127.0.0.1")
    }

    @Test("close()가 transport.disconnect()를 호출한다")
    func closeCallsDisconnect() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let sessionHarness = await harness.simulateClientConnection()

        #expect(!sessionHarness.clientTransport.disconnectCalled)

        await sessionHarness.session.close()

        #expect(sessionHarness.clientTransport.disconnectCalled)
        await harness.waitForSessionsEmpty()
        #expect(await harness.server.sessions.isEmpty)
    }

    @Test("close()는 메인 채널을 teardown한다")
    func closeTearsDownMainChannel() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let sessionHarness = await harness.simulateClientConnection()
        let (_, stream) = try await sessionHarness.openMainChannel()

        await sessionHarness.session.close()

        #expect(stream.isClosed)
        #expect(await sessionHarness.session.channelManager.mainChannel == nil)
    }
}
