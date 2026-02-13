//
//  ErrorHandlingTests.swift
//  SiriusKitClientTests
//

import Testing
import Foundation

@testable import SiriusKitCore
@testable import SiriusKitClient

@Suite("Error Handling Tests")
struct ErrorHandlingTests {

    @Test("connect() 실패 시 에러가 전파된다")
    func connectFailurePropagatesError() async throws {
        let harness = TestHarness()
        harness.transport.connectError = ClientTransportError.connectionFailed(description: "test")

        await #expect(throws: ClientTransportError.self) {
            try await harness.client.startup()
        }
    }

    @Test("트랜스포트 에러 시 delegate에 에러가 전달된다")
    func transportErrorNotifiesDelegate() async throws {
        let harness = TestHarness()
        try await harness.startup()

        #expect(harness.delegate.lastError == nil)

        await harness.transport.simulateError(ClientTransportError.certificateValidationFailed)

        #expect(harness.delegate.lastError is ClientTransportError)
    }

    @Test("트랜스포트 종료 시 delegate.didCloseTransport이 호출된다")
    func transportCloseNotifiesDelegate() async throws {
        let harness = TestHarness()
        try await harness.startup()

        #expect(!harness.delegate.didCloseTransport)

        await harness.transport.simulateClose()

        #expect(harness.delegate.didCloseTransport)
    }
}
