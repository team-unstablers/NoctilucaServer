//
//  MockSiriusServerDelegate.swift
//  SiriusKitTests
//

import Foundation
@testable import SiriusKitCore
@testable import SiriusKit

final class MockSiriusServerDelegate: SiriusServerDelegate, @unchecked Sendable {
    private(set) var didStart = false
    private(set) var didStop = false
    private(set) var lastError: Error?
    private(set) var acceptedSessions: [ClientSession] = []

    func siriusServerDidStart(_ server: SiriusServer) {
        didStart = true
    }

    func siriusServerDidStop(_ server: SiriusServer) {
        didStop = true
    }

    func siriusServer(_ server: SiriusServer, didEncounterError error: any Error) {
        lastError = error
    }

    func siriusServerDidAcceptClientSession(_ server: SiriusServer, session: ClientSession) async {
        acceptedSessions.append(session)
    }

    func siriusServerDidFailToAcceptClientSession(_ server: SiriusServer, error: any Error) {
        lastError = error
    }
}
