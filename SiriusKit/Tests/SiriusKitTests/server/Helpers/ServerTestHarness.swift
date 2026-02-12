//
//  ServerTestHarness.swift
//  SiriusKitTests
//

import Foundation
@testable import SiriusKitCore
@testable import SiriusKit

struct ServerTestHarness {
    let rootTransport: MockServerRoleRootTransport
    let featureProvider: MockFeatureProvider
    let serverDelegate: MockSiriusServerDelegate
    let server: SiriusServer

    init() {
        rootTransport = MockServerRoleRootTransport()
        featureProvider = MockFeatureProvider()
        serverDelegate = MockSiriusServerDelegate()
        server = SiriusServer(serverTransport: rootTransport, featureProvider: featureProvider)
        server.delegate = serverDelegate
    }

    func startup() async throws {
        try await server.startup()
    }

    func shutdown() async throws {
        try await server.shutdown()
    }

    /// 클라이언트 접속을 시뮬레이션하고 SessionHarness를 반환한다.
    @discardableResult
    func simulateClientConnection(
        channelOpenTimeout: TimeInterval = 5
    ) -> SessionHarness {
        let clientTransport = MockServerRoleClientTransport()
        rootTransport.simulateClientConnection(clientTransport)

        let session = serverDelegate.acceptedSessions.last!
        return SessionHarness(
            session: session,
            clientTransport: clientTransport,
            channelOpenTimeout: channelOpenTimeout
        )
    }
}

struct SessionHarness {
    let session: ClientSession
    let clientTransport: MockServerRoleClientTransport
    let sessionDelegate: MockClientSessionDelegate

    init(
        session: ClientSession,
        clientTransport: MockServerRoleClientTransport,
        channelOpenTimeout: TimeInterval = 5
    ) {
        self.session = session
        self.clientTransport = clientTransport
        self.sessionDelegate = MockClientSessionDelegate()
        session.delegate = sessionDelegate

        if channelOpenTimeout != 5 {
            session.channelManager = ChannelManager(
                session: session,
                channelOpenTimeout: channelOpenTimeout
            )
        }
    }

    /// 첫 스트림을 열어 메인 채널을 생성한다.
    @discardableResult
    func openMainChannel() async throws -> (mainChannel: MainChannel, stream: MockStream) {
        let stream = MockStream()
        try await clientTransport.simulateRemoteStreamOpen(stream)
        let mainChannel = try await sessionDelegate.waitForMainChannel()
        return (mainChannel, stream)
    }
}
