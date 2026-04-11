//
//  MockServerRoleRootTransport.swift
//  SiriusKitTests
//

import Foundation
@testable import SiriusKitCore
@testable import SiriusKit

final class MockServerRoleRootTransport: ServerRoleRootTransport, @unchecked Sendable {
    weak var delegate: ServerRoleRootTransportDelegate?

    // MARK: - Tracking

    private(set) var startupCalled = false
    private(set) var shutdownCalled = false

    // MARK: - Configuration

    var startupError: Error?

    // MARK: - Protocol

    func startup() async throws {
        startupCalled = true

        if let error = startupError {
            throw error
        }

        delegate?.serverTransportDidStartListening(self)
    }

    func shutdown() async throws {
        shutdownCalled = true
        delegate?.serverTransportDidStopListening(self)
    }

    // MARK: - Simulation (non-async)

    func simulateClientConnection(_ clientTransport: MockServerRoleClientTransport) {
        delegate?.serverTransportDidAcceptConnection(self, clientTransport: clientTransport)
    }

    func simulateError(_ error: Error) {
        delegate?.serverTransport(self, didEncounterError: error)
    }

    func simulateConnectionFailure(_ error: Error) {
        delegate?.serverTransportDidFailToAcceptConnection(self, error: error)
    }
}
