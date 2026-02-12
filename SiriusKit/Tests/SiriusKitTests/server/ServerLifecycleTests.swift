//
//  ServerLifecycleTests.swift
//  SiriusKitTests
//

import Testing
import Foundation

@testable import SiriusKitCore
@testable import SiriusKit

@Suite("Server Lifecycle Tests")
struct ServerLifecycleTests {

    @Test("startup()이 rootTransport.startup()을 호출한다")
    func startupCallsRootTransportStartup() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        #expect(harness.rootTransport.startupCalled)
    }

    @Test("startup 성공 시 delegate.siriusServerDidStart가 호출된다")
    func startupNotifiesDelegate() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()

        #expect(harness.serverDelegate.didStart)
    }

    @Test("shutdown 후 delegate.siriusServerDidStop이 호출된다")
    func shutdownNotifiesDelegate() async throws {
        let harness = ServerTestHarness()
        try await harness.startup()
        try await harness.shutdown()

        #expect(harness.rootTransport.shutdownCalled)
        #expect(harness.serverDelegate.didStop)
    }
}
