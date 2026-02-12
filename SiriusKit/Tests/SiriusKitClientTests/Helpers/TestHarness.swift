//
//  TestHarness.swift
//  SiriusKitClientTests
//

import Foundation
@testable import SiriusKitCore
@testable import SiriusKitClient

struct TestHarness {
    let mainChannelStream: MockStream
    let transport: MockClientRoleTransport
    let featureProvider: MockFeatureProvider
    let delegate: MockSiriusClientDelegate
    let client: SiriusClient

    init(channelOpenTimeout: TimeInterval = 5) {
        mainChannelStream = MockStream()
        transport = MockClientRoleTransport()
        transport.enqueueMockStream(mainChannelStream)
        featureProvider = MockFeatureProvider()
        delegate = MockSiriusClientDelegate()
        client = SiriusClient(transport: transport, featureProvider: featureProvider)

        if channelOpenTimeout != 5 {
            client.channelManager = ChannelManager(session: client, channelOpenTimeout: channelOpenTimeout)
        }

        client.delegate = delegate
    }

    func startup() async throws {
        try await client.startup()
    }

    var mainChannel: MainChannel? {
        get async { await client.channelManager.mainChannel }
    }
}
