//
//  MockSiriusClientDelegate.swift
//  SiriusKitClientTests
//

import Foundation
@testable import SiriusKitCore
@testable import SiriusKitClient

final class MockSiriusClientDelegate: SiriusClientDelegate {
    private(set) var mainChannel: MainChannel?
    private(set) var didCloseTransport = false

    private var mainChannelContinuation: CheckedContinuation<MainChannel, Never>?

    func siriusClient(_ client: SiriusClient, didCreateMainChannel mainChannel: MainChannel) {
        self.mainChannel = mainChannel
        mainChannelContinuation?.resume(returning: mainChannel)
        mainChannelContinuation = nil
    }

    func siriusClientDidCloseTransport(_ client: SiriusClient) {
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
