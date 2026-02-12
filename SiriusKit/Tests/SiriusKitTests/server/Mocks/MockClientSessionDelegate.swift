//
//  MockClientSessionDelegate.swift
//  SiriusKitTests
//

import Foundation
@testable import SiriusKitCore
@testable import SiriusKit

final class MockClientSessionDelegate: ClientSessionDelegate {
    private(set) var mainChannel: MainChannel?
    private(set) var didCloseTransport = false

    private var mainChannelContinuation: CheckedContinuation<MainChannel, Never>?

    func clientSessionDidCreateMainChannel(_ session: ClientSession, mainChannel: MainChannel) {
        self.mainChannel = mainChannel
        mainChannelContinuation?.resume(returning: mainChannel)
        mainChannelContinuation = nil
    }

    func clientSessionDidCloseTransport(_ session: ClientSession) {
        didCloseTransport = true
    }

    func waitForMainChannel(timeout: TimeInterval = 2) async throws -> MainChannel {
        if let mainChannel = mainChannel {
            return mainChannel
        }

        return await withCheckedContinuation { continuation in
            self.mainChannelContinuation = continuation
        }
    }
}
