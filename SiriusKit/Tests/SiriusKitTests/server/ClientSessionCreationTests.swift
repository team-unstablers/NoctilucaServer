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

        harness.simulateClientConnection()

        #expect(harness.server.sessions.count == 1)
    }

    @Test("delegate.siriusServerDidAcceptClientSession이 호출된다")
    func delegateNotifiedOnSessionCreation() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        harness.simulateClientConnection()

        #expect(harness.serverDelegate.acceptedSessions.count == 1)
    }

    @Test("ClientSession의 remoteAddress가 올바르게 설정된다")
    func sessionHasCorrectRemoteAddress() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let sessionHarness = harness.simulateClientConnection()

        #expect(sessionHarness.session.remoteAddress == "127.0.0.1")
    }

    @Test("close()가 transport.disconnect()를 호출한다")
    func closeCallsDisconnect() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let sessionHarness = harness.simulateClientConnection()

        #expect(!sessionHarness.clientTransport.disconnectCalled)

        await sessionHarness.session.close()

        #expect(sessionHarness.clientTransport.disconnectCalled)
    }
}
