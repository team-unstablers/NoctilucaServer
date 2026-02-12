//
//  MockClientRoleTransport.swift
//  SiriusKitClientTests
//

import Foundation
@testable import SiriusKitCore
@testable import SiriusKitClient

final class MockClientRoleTransport: ClientRoleTransport {
    let id: TransportLayerIdentifier = UUID()

    weak var delegate: ClientRoleTransportDelegate?

    var hostname: String = "localhost"
    var port: UInt16 = 8282
    var identity: ServerIdentity? = nil
    var identityValidationPolicy: ServerIdentityValidationPolicy = .dangerouslyAllowAlwaysWithoutValidation

    // MARK: - Tracking

    private(set) var connectCalled = false
    private(set) var disconnectCalled = false
    private(set) var openStreamCallCount = 0

    // MARK: - Configuration

    var connectError: Error?
    private var streamQueue: [MockStream] = []

    func enqueueMockStream(_ stream: MockStream) {
        streamQueue.append(stream)
    }

    // MARK: - Protocol

    func connect() async throws {
        connectCalled = true

        if let error = connectError {
            throw error
        }

        await delegate?.clientTransportDidEstablishConnection(self)
    }

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

    // MARK: - Simulation

    func simulateRemoteStreamOpen(_ stream: MockStream) async throws {
        try await delegate?.clientTransportDidOpenRemoteStream(self, stream: stream)
    }

    func simulateError(_ error: Error) async {
        await delegate?.clientTransport(self, didEncounterError: error)
    }

    func simulateClose() async {
        await delegate?.clientTransportDidClose(self)
    }
}
