//
//  MockServerRoleClientTransport.swift
//  SiriusKitTests
//

import Foundation
@testable import SiriusKitCore
@testable import SiriusKit

final class MockServerRoleClientTransport: ServerRoleClientTransport, @unchecked Sendable {
    let id: TransportLayerIdentifier = UUID()
    private let loggerContext = SharedState(SiriusEventLogger.Context())

    weak var delegate: ServerRoleClientTransportDelegate?

    var remoteEndpoint: SREndpoint? = SREndpoint(address: .IPv4(0x7F000001))
    var isClosed: Bool = false

    // MARK: - Tracking

    private(set) var disconnectCalled = false
    private(set) var openStreamCallCount = 0
    private(set) var issueResumeTicketCalled = false

    // MARK: - Configuration

    private var streamQueue: [MockStream] = []
    private var openStreams: [StreamIdentifier: SiriusKitCore.Stream] = [:]

    func enqueueMockStream(_ stream: MockStream) {
        streamQueue.append(stream)
    }

    // MARK: - Protocol

    func disconnect() async {
        disconnectCalled = true
        isClosed = true
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

    func getStreams() async -> [StreamIdentifier: SiriusKitCore.Stream] {
        openStreams
    }

    func eventLoggerContext() -> SharedState<SiriusEventLogger.Context> {
        loggerContext
    }

    // MARK: - Simulation (async)

    func simulateRemoteStreamOpen(_ stream: MockStream) async throws {
        openStreams[stream.id()] = stream
        try await delegate?.clientTransportDidOpenRemoteStream(self, stream: stream)
    }

    func simulateClose() async {
        isClosed = true
        await delegate?.clientTransportDidClose(self)
    }

    func simulateError(_ error: Error) async {
        await delegate?.clientTransport(self, didEncounterError: error)
    }
}
