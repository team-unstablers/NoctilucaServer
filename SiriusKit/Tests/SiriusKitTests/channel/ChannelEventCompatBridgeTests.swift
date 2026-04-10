//
//  ChannelEventCompatBridgeTests.swift
//  SiriusKitTests
//
//  ChannelEventCompatBridge 가 ChannelHandle.events 를 ChannelEventConsumer 에게
//  올바르게 중계하는지 검증한다.
//

import Testing
import Foundation

@testable import SiriusKitCore

// MARK: - Mock consumer

final class MockChannelEventConsumer: ChannelEventConsumer, @unchecked Sendable {
    enum Recorded: Sendable {
        case ready
        case frame(SiriusFrame)
        case error(String)
        case closed
    }

    private let lock = NSLock()
    private var _events: [Recorded] = []
    var shouldThrowOnFrame = false

    var events: [Recorded] {
        lock.withLock { _events }
    }

    func handleChannelReady() async {
        lock.withLock { _events.append(.ready) }
    }

    func handleFrame(frame: SiriusFrame) async throws {
        lock.withLock { _events.append(.frame(frame)) }
        if shouldThrowOnFrame {
            throw ChannelError.invalidFrame
        }
    }

    func handleError(error: Error) async {
        lock.withLock { _events.append(.error("\(error)")) }
    }

    func handleStreamClose() async {
        lock.withLock { _events.append(.closed) }
    }
}

// MARK: - Suite

@Suite("ChannelEventCompatBridge Relay Tests")
struct ChannelEventCompatBridgeTests {

    private struct Fixture {
        let session: MockSiriusSession
        let stream: MockStream
        let handle: ChannelHandleImpl
        let consumer: MockChannelEventConsumer

        init() {
            session = MockSiriusSession()
            stream = MockStream()
            handle = ChannelHandleImpl(
                feature: .init(rawValue: .zero),
                session: session,
                stream: stream,
                identifier: UUID(),
                direction: .local
            )
            consumer = MockChannelEventConsumer()
        }
    }

    private func waitUntil(
        timeoutSeconds: TimeInterval = 2,
        _ condition: @Sendable @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while Date() < deadline {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    @Test("activate 시 consumer.handleChannelReady 가 호출된다")
    func bridgeRelaysReadyEvent() async throws {
        let f = Fixture()
        let bridge = ChannelEventCompatBridge(consumer: f.consumer, handle: f.handle)

        try await f.handle.activate()

        await waitUntil {
            f.consumer.events.contains { if case .ready = $0 { return true } else { return false } }
        }

        #expect(f.consumer.events.contains { if case .ready = $0 { return true } else { return false } })

        try await f.handle.close()
        _ = bridge  // hold until end of scope
    }

    @Test("stream frame 주입 시 consumer.handleFrame 이 호출된다")
    func bridgeRelaysFrameReceivedEvent() async throws {
        let f = Fixture()
        let bridge = ChannelEventCompatBridge(consumer: f.consumer, handle: f.handle)

        try await f.handle.activate()
        f.stream.injectFrame(SiriusFrame(opcode: .ping, length: 1, data: Data([0x77])))

        await waitUntil {
            f.consumer.events.contains { if case .frame = $0 { return true } else { return false } }
        }

        #expect(f.consumer.events.contains {
            if case .frame(let frame) = $0 {
                return frame.data == Data([0x77])
            } else {
                return false
            }
        })

        try await f.handle.close()
        _ = bridge
    }

    @Test("stream error 주입 시 consumer.handleError 가 호출된다")
    func bridgeRelaysErrorEvent() async throws {
        let f = Fixture()
        let bridge = ChannelEventCompatBridge(consumer: f.consumer, handle: f.handle)

        try await f.handle.activate()
        f.stream.injectError(StreamError.aborted)

        await waitUntil {
            f.consumer.events.contains { if case .error = $0 { return true } else { return false } }
        }

        #expect(f.consumer.events.contains { if case .error = $0 { return true } else { return false } })

        _ = bridge
    }

    @Test("stream close 주입 시 consumer.handleStreamClose 가 호출된다")
    func bridgeRelaysStreamCloseEvent() async throws {
        let f = Fixture()
        let bridge = ChannelEventCompatBridge(consumer: f.consumer, handle: f.handle)

        try await f.handle.activate()
        f.stream.injectClose()

        await waitUntil {
            f.consumer.events.contains { if case .closed = $0 { return true } else { return false } }
        }

        #expect(f.consumer.events.contains { if case .closed = $0 { return true } else { return false } })

        _ = bridge
    }

    @Test("consumer.handleFrame 이 throw 해도 bridge task 는 다음 이벤트를 계속 소화한다")
    func bridgeSwallowsHandleFrameThrow() async throws {
        let f = Fixture()
        let bridge = ChannelEventCompatBridge(consumer: f.consumer, handle: f.handle)

        f.consumer.shouldThrowOnFrame = true

        try await f.handle.activate()

        f.stream.injectFrame(SiriusFrame(opcode: .ping, length: 1, data: Data([0x01])))

        // frame 1 기록까지 대기
        await waitUntil {
            f.consumer.events.filter { if case .frame = $0 { return true } else { return false } }.count >= 1
        }

        // 두번째 frame도 정상적으로 처리되어야 한다 (첫번째 throw가 bridge loop를 죽이지 않았는지)
        f.stream.injectFrame(SiriusFrame(opcode: .ping, length: 1, data: Data([0x02])))

        await waitUntil {
            f.consumer.events.filter { if case .frame = $0 { return true } else { return false } }.count >= 2
        }

        let frameCount = f.consumer.events.filter { if case .frame = $0 { return true } else { return false } }.count
        #expect(frameCount >= 2)

        try await f.handle.close()
        _ = bridge
    }
}
