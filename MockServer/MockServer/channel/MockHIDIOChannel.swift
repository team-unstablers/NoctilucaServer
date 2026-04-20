//
//  MockHIDIOChannel.swift
//  MockServer
//
//  Created by Gyuhwan Park on 2/13/26.
//

import SiriusKit

/// HIDIO 채널의 더미 구현. 클라이언트로부터 수신되는 입력 이벤트를 무시한다.
final class MockHIDIOChannel: Channel, ChannelEventConsumer {
    private let logger = SiriusLogger(category: "MockHIDIOChannel", subsystem: "app.noctiluca.mockserver")

    let handle: ChannelHandle

    private static let defaultServiceClass: ServiceClass = .userInput

    nonisolated(unsafe) private var channelEventCompatBridge:
        ChannelEventCompatBridge<MockHIDIOChannel>!

    init(handle: ChannelHandle) {
        self.handle = handle
        self.channelEventCompatBridge =
            ChannelEventCompatBridge(consumer: self, handle: handle)
    }

    // MARK: - ChannelEventConsumer

    func handleChannelReady() async {
        await handle.setServiceClass(Self.defaultServiceClass)
    }

    func handleFrame(frame: SiriusFrame) async throws {
        // 모든 HIDIO 프레임 무시
        logger.trace("Ignoring HIDIO frame: opcode=\(frame.opcode)")
    }

    func handleError(error: any Error) async {
        // no-op
    }

    func handleStreamClose() async {
        // no-op
    }
}
