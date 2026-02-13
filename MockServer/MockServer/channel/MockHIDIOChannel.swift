//
//  MockHIDIOChannel.swift
//  MockServer
//
//  Created by Gyuhwan Park on 2/13/26.
//

import SiriusKit

/// HIDIO 채널의 더미 구현. 클라이언트로부터 수신되는 입력 이벤트를 무시한다.
class MockHIDIOChannel: Channel {
    private let logger = SiriusLogger(category: "MockHIDIOChannel", subsystem: "app.noctiluca.mockserver")

    override var serviceClass: ServiceClass { .userInput }

    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        super.init(using: streamHolder, identifier: identifier, direction: direction)
    }

    override func handleFrame(frame: SiriusFrame) async throws {
        // 모든 HIDIO 프레임 무시
        logger.trace("Ignoring HIDIO frame: opcode=\(frame.opcode)")
    }
}
