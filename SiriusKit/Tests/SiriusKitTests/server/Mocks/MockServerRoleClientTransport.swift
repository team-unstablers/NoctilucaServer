//
//  MockServerRoleClientTransport.swift
//  SiriusKitTests
//

import Foundation
@testable import SiriusKitCore
@testable import SiriusKit

final class MockServerRoleClientTransport: ServerRoleClientTransport {
    let id: TransportLayerIdentifier = UUID()

    weak var delegate: ServerRoleClientTransportDelegate?

    var remoteAddress: String? = "127.0.0.1"

    // MARK: - Tracking

    private(set) var disconnectCalled = false
    private(set) var openStreamCallCount = 0
    private(set) var issueResumeTicketCalled = false

    // MARK: - Configuration

    private var streamQueue: [MockStream] = []

    func enqueueMockStream(_ stream: MockStream) {
        streamQueue.append(stream)
    }

    // MARK: - Protocol

    func disconnect() async {
        disconnectCalled = true
    }

    func openStream() async -> Result<SiriusKitCore.Stream, TransportLayerError> {
        openStreamCallCount += 1

        guard !streamQueue.isEmpty else {
            return .failure(.openStreamFailed(error: nil))
        }
        return .success(streamQueue.removeFirst())
    }

    func issueResumeTicket() async throws {
        issueResumeTicketCalled = true
    }

    // MARK: - Simulation (async)

    func simulateRemoteStreamOpen(_ stream: MockStream) async throws {
        try await delegate?.clientTransportDidOpenRemoteStream(self, stream: stream)
    }

    func simulateClose() async {
        await delegate?.clientTransportDidClose(self)
    }

    func simulateError(_ error: Error) async {
        await delegate?.clientTransport(self, didEncounterError: error)
    }
}
