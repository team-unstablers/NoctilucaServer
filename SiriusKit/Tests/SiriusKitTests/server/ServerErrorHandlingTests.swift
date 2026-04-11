//
//  ServerErrorHandlingTests.swift
//  SiriusKitTests
//

import Testing
import Foundation

@testable import SiriusKitCore
@testable import SiriusKit

@Suite("Server Error Handling Tests")
struct ServerErrorHandlingTests {

    @Test("rootTransport 에러 시 server delegate에 전달된다")
    func rootTransportErrorNotifiesDelegate() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        #expect(harness.serverDelegate.lastError == nil)

        harness.rootTransport.simulateError(TransportLayerError.connectionFailed(error: nil))

        #expect(harness.serverDelegate.lastError != nil)
    }

    @Test("트랜스포트 종료 시 delegate.clientSessionDidCloseTransport이 호출된다")
    func transportCloseNotifiesSessionDelegate() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let sessionHarness = harness.simulateClientConnection()
        try await sessionHarness.openMainChannel()

        #expect(!sessionHarness.sessionDelegate.didCloseTransport)

        await sessionHarness.clientTransport.simulateClose()

        #expect(sessionHarness.sessionDelegate.didCloseTransport)
        #expect(await harness.server.sessions.isEmpty)
    }

    @Test("여러 클라이언트가 동시에 접속할 수 있다")
    func multipleClientsCanConnect() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let session1 = harness.simulateClientConnection()
        let session2 = harness.simulateClientConnection()
        let session3 = harness.simulateClientConnection()

        #expect(await harness.server.sessions.count == 3)
        #expect(harness.serverDelegate.acceptedSessions.count == 3)

        // 각 세션이 독립적으로 메인 채널을 가질 수 있다
        try await session1.openMainChannel()
        try await session2.openMainChannel()

        #expect(session1.sessionDelegate.mainChannel != nil)
        #expect(session2.sessionDelegate.mainChannel != nil)
        #expect(session3.sessionDelegate.mainChannel == nil)

        // 세션 1 종료가 세션 2에 영향을 주지 않는다
        await session1.clientTransport.simulateClose()

        #expect(session1.sessionDelegate.didCloseTransport)
        #expect(!session2.sessionDelegate.didCloseTransport)
        #expect(await harness.server.sessions.count == 2)
    }

    @Test("이미 닫힌 transport는 ClientSession을 만들지 않는다")
    func closedTransportIsNotAcceptedAsSession() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        let clientTransport = MockServerRoleClientTransport()
        clientTransport.isClosed = true

        harness.rootTransport.simulateClientConnection(clientTransport)

        #expect(await harness.server.sessions.isEmpty)
        #expect(harness.serverDelegate.acceptedSessions.isEmpty)
    }
}
