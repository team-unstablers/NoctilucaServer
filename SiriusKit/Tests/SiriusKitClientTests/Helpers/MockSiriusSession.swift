//
//  MockSiriusSession.swift
//  SiriusKitClientTests
//
//  ChannelHandleImpl 단위 테스트용으로 최소한의 SiriusSession 구현체.
//  상위 Harness(TestHarness)를 거치지 않고 ChannelHandleImpl을 독립적으로
//  생성·조작할 때 사용한다.
//

import Foundation
@testable import SiriusKitCore

final class MockSiriusSession: SiriusSession, @unchecked Sendable {
    let id: UUID = UUID()

    var shouldAcceptChannelCreation: Bool = true

    let transport: any TransportLayer
    let featureProvider: any FeatureProvider

    init(
        transport: any TransportLayer = StubTransportLayer(),
        featureProvider: any FeatureProvider = MockFeatureProvider()
    ) {
        self.transport = transport
        self.featureProvider = featureProvider
    }
}

/// ChannelHandleImpl의 unit test에서는 transport가 쓰이지 않으므로 stub만 둔다.
final class StubTransportLayer: TransportLayer, @unchecked Sendable {
    let id: TransportLayerIdentifier = UUID()

    func disconnect() async {
        // no-op
    }

    func openStream() async -> Result<SiriusKitCore.Stream, TransportLayerError> {
        .failure(.notImplemented)
    }
}
