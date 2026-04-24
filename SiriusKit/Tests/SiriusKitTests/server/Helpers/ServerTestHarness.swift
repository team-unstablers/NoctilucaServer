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
    }

    func startup() async throws {
        await server.setDelegate(serverDelegate)
        try await server.startup()
    }

    func shutdown() async throws {
        try await server.shutdown()
    }

    /// 클라이언트 접속을 시뮬레이션하고 SessionHarness를 반환한다.
    ///
    /// `MockServerRoleRootTransport.simulateClientConnection`은 동기 호출이지만,
    /// `SiriusServer`가 내부적으로 `Task { await createClientSession(...) }`로
    /// fire-and-forget 처리하기 때문에, 본 헬퍼가 반환되는 시점에
    /// `serverDelegate.acceptedSessions`가 아직 비어있을 수 있다.
    ///
    /// 이 메서드는 세션이 실제로 delegate에 기록될 때까지 폴링하며 대기한다.
    /// (c062434에서 `siriusServerDidAcceptClientSession`이 async로 변경되면서
    /// 레이스가 심해졌음)
    /// 서버의 `sessions`가 비어있을 때까지 대기한다.
    ///
    /// `ClientSession.close()`는 `clientSessionDidClose` 콜백을 통해 비동기적으로
    /// `Task { await self.removeSession(...) }`를 통해 세션을 제거하기 때문에,
    /// `close()`가 반환된 직후에는 아직 `sessions`가 비어있지 않을 수 있다.
    func waitForSessionsEmpty(timeout: TimeInterval = 2) async {
        await waitForSessionsCount(0, timeout: timeout)
    }

    /// 서버의 `sessions.count`가 특정 값이 될 때까지 대기한다.
    func waitForSessionsCount(_ expected: Int, timeout: TimeInterval = 2) async {
        let deadline = Date().addingTimeInterval(timeout)
        while await server.sessions.count != expected {
            if Date() > deadline { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    /// 임의의 조건이 `true`가 될 때까지 대기한다.
    ///
    /// `SiriusServer`의 delegate 콜백(`siriusServerDidStart/Stop`, `siriusServer(_:didEncounterError:)`)
    /// 등은 `nonisolated`에서 `Task { ... }`로 전달되기 때문에, 트리거 직후 즉시 검증하면 race가 발생한다.
    /// 테스트에서 이 헬퍼로 조건을 기다린다.
    func waitUntil(
        timeout: TimeInterval = 2,
        pollInterval: TimeInterval = 0.005,
        _ condition: @Sendable () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline { return }
            try? await Task.sleep(for: .seconds(pollInterval))
        }
    }

    @discardableResult
    func simulateClientConnection(
        channelOpenTimeout: TimeInterval = 5,
        acceptTimeout: TimeInterval = 2
    ) async -> SessionHarness {
        let initialCount = serverDelegate.acceptedSessions.count
        let clientTransport = MockServerRoleClientTransport()
        rootTransport.simulateClientConnection(clientTransport)

        let deadline = Date().addingTimeInterval(acceptTimeout)
        while serverDelegate.acceptedSessions.count <= initialCount {
            if Date() > deadline {
                fatalError("ServerTestHarness.simulateClientConnection(): timed out waiting for session to be accepted (\(acceptTimeout)s)")
            }
            try? await Task.sleep(for: .milliseconds(5))
        }

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
