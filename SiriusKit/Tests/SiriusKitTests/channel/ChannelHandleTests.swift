//
//  ChannelHandleTests.swift
//  SiriusKitTests
//
//  ChannelHandleImpl(ChannelHandle 프로토콜의 표준 구현체)의 동작 스펙을 검증한다.
//  테스트의 기준은 "현재 구현이 무엇을 하는가"가 아니라 "ChannelHandle이 무엇을
//  약속해야 하는가"이며, 따라서 실패할 경우 구현 버그의 신호로 간주해야 한다.
//
//  - 출처: SiriusKit/Sources/SiriusKitCore/channel/ChannelHandle.swift 의 doc comment
//  - 커밋: 436c6f9d "siriuskit/channel: Channel을 프로토콜로 재설계 및 ChannelHandle 도입"
//

import Testing
import Foundation

@testable import SiriusKitCore

// MARK: - 헬퍼: 관찰 가능한 lifecycle delegate

final class ObservingLifecycleDelegate: ChannelLifecycleDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _didCloseChannels: [ChannelIdentifier] = []
    private var _encounteredErrors: [(ChannelIdentifier, String)] = []

    var didCloseChannels: [ChannelIdentifier] {
        lock.withLock { _didCloseChannels }
    }
    var encounteredErrors: [(ChannelIdentifier, String)] {
        lock.withLock { _encounteredErrors }
    }

    func channelDidClose(_ channel: any ChannelHandle) {
        lock.withLock { _didCloseChannels.append(channel.identifier) }
    }

    func channel(_ channel: any ChannelHandle, didEncounterError error: any Error) {
        lock.withLock { _encounteredErrors.append((channel.identifier, "\(error)")) }
    }
}

// MARK: - 테스트용 프레임/스트림 헬퍼

private enum ChannelHandleTestFrames {
    static func simpleFrame(_ payload: [UInt8] = [0x00]) -> SiriusFrame {
        let data = Data(payload)
        return SiriusFrame(opcode: .ping, length: UInt32(data.count), data: data)
    }

    static func frame(opcode: MessageOpcode, payload: [UInt8]) -> SiriusFrame {
        let data = Data(payload)
        return SiriusFrame(opcode: opcode, length: UInt32(data.count), data: data)
    }
}

private struct ChannelHandleFixture {
    let session: MockSiriusSession
    let stream: MockStream
    let handle: ChannelHandleImpl

    init(
        feature: SiriusFeature = .hidio,
        direction: ChannelDirection = .local
    ) {
        self.session = MockSiriusSession()
        self.stream = MockStream()
        self.handle = ChannelHandleImpl(
            feature: feature,
            session: session,
            stream: stream,
            identifier: UUID(),
            direction: direction
        )
    }
}

// MARK: - Suite

@Suite("ChannelHandleImpl Contract Tests")
struct ChannelHandleTests {

    // MARK: - Activation / Idempotence

    @Test("활성화 직후 send(frame:)은 즉시 stream에 기록된다")
    func activate_transitionsFromPreActivationToActive() async throws {
        let f = ChannelHandleFixture()
        try await f.handle.activate()

        try await f.handle.send(frame: ChannelHandleTestFrames.simpleFrame([0xAA]))

        #expect(f.stream.writtenFrames.count == 1)
        #expect(f.stream.writtenFrames[0].opcode == .ping)

        try await f.handle.close()
    }

    @Test("activate()는 idempotent하다 (두 번 호출해도 에러가 없다)")
    func activate_isIdempotent() async throws {
        let f = ChannelHandleFixture()
        try await f.handle.activate()
        try await f.handle.activate()

        try await f.handle.send(frame: ChannelHandleTestFrames.simpleFrame())
        #expect(f.stream.writtenFrames.count == 1)

        try await f.handle.close()
    }

    @Test("close() 이후의 activate()는 ChannelError.channelClosed를 throw한다")
    func activate_afterClose_throwsChannelClosed() async throws {
        let f = ChannelHandleFixture()
        try await f.handle.close()

        await #expect(throws: ChannelError.self) {
            try await f.handle.activate()
        }
    }

    // MARK: - Send buffering (pre-activation)

    @Test("pre-activation send(frame:) 은 버퍼링되어 stream에 즉시 기록되지 않는다")
    func sendFrame_beforeActivate_isBuffered() async throws {
        let f = ChannelHandleFixture()
        let frame = ChannelHandleTestFrames.simpleFrame([0x11])

        let sendTask = Task {
            try await f.handle.send(frame: frame)
        }

        // 실제로 쓰기가 발생하지 않았음을 짧은 슬립 후 확인
        try await Task.sleep(nanoseconds: 20_000_000) // 20ms
        #expect(f.stream.writtenFrames.isEmpty)

        // activate → 쓰기 flush → task 정상 return
        try await f.handle.activate()
        try await sendTask.value

        #expect(f.stream.writtenFrames.count == 1)
        #expect(f.stream.writtenFrames[0].data == Data([0x11]))

        try await f.handle.close()
    }

    @Test("pre-activation send(opcode:message:) 도 버퍼링된다")
    func sendOpcodeMessage_beforeActivate_isBuffered() async throws {
        let f = ChannelHandleFixture()
        let hello = ClientHello(protocolVersion: .v1_0, agentName: "bufferTest")

        let sendTask = Task {
            try await f.handle.send(opcode: .clientHello, message: hello)
        }

        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(f.stream.writtenFrames.isEmpty)

        try await f.handle.activate()
        try await sendTask.value

        let written = f.stream.frames(withOpcode: .clientHello)
        #expect(written.count == 1)

        try await f.handle.close()
    }

    @Test("pre-activation nonblocking send도 버퍼링된다")
    func sendNonblocking_beforeActivate_isBuffered() async throws {
        let f = ChannelHandleFixture()

        f.handle.send(nonblocking: ChannelHandleTestFrames.simpleFrame([0xBB]))
        try await Task.sleep(nanoseconds: 20_000_000)

        #expect(f.stream.writtenFrames.isEmpty)

        try await f.handle.activate()
        // activate 시 drain → 기록
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(f.stream.writtenFrames.count == 1)

        try await f.handle.close()
    }

    @Test("nonblocking만으로 버퍼링된 여러 send는 activate 시 FIFO 순서로 flush된다")
    func bufferedNonblockingSends_flushOnActivateInFIFOOrder() async throws {
        // 단일 호출 스레드에서 nonblocking send 를 순차적으로 호출하면 호출 순서가
        // enqueue 순서와 정확히 일치해야 한다.
        let f = ChannelHandleFixture()

        let payloads: [[UInt8]] = [[0x01], [0x02], [0x03], [0x04], [0x05]]
        for p in payloads {
            f.handle.send(nonblocking: ChannelHandleTestFrames.simpleFrame(p))
        }

        try await f.handle.activate()

        let written = f.stream.writtenFrames
        #expect(written.count == payloads.count)
        for (idx, p) in payloads.enumerated() {
            #expect(written[idx].data == Data(p))
        }

        try await f.handle.close()
    }

    @Test("버퍼링된 여러 async send는 activate 시 enqueue 된 순서로 flush된다")
    func bufferedAsyncSends_flushOnActivateInFIFOOrder() async throws {
        // 스펙상 _pendingSends 는 FIFO 큐이므로, enqueue 된 순서대로 flush 되어야 한다.
        // Task kick-off 순서가 실제 _pendingSends 진입 순서와 일치하지 않을 가능성이
        // 있지만, 그게 구현상 race 라면 이 테스트가 실패로 드러낼 것이다.
        let f = ChannelHandleFixture()

        let payloads: [[UInt8]] = [[0x01], [0x02], [0x03], [0x04], [0x05]]

        let tasks: [Task<Void, Error>] = payloads.map { p in
            Task {
                try await f.handle.send(frame: ChannelHandleTestFrames.simpleFrame(p))
            }
        }

        // 모든 task가 버퍼에 enqueue 될 시간 확보
        try await Task.sleep(nanoseconds: 30_000_000)

        try await f.handle.activate()
        for task in tasks { try await task.value }

        let written = f.stream.writtenFrames
        #expect(written.count == payloads.count)
        for (idx, p) in payloads.enumerated() {
            #expect(written[idx].data == Data(p))
        }

        try await f.handle.close()
    }

    @Test("async와 nonblocking이 혼재된 pre-activate send도 호출 순서대로 flush된다")
    func mixedAsyncAndNonblockingBufferedSends_flushInCallOrder() async throws {
        // 스펙: _pendingSends 는 async/nonblocking 이 섞여 있어도 호출 순서대로
        // enqueue 되고, activate 시 그 순서대로 flush 된다.
        let f = ChannelHandleFixture()

        // call order: async(1), nonblocking(2), async(3), nonblocking(4)
        let t1 = Task {
            try await f.handle.send(frame: ChannelHandleTestFrames.simpleFrame([0x01]))
        }
        try await Task.sleep(nanoseconds: 10_000_000)

        f.handle.send(nonblocking: ChannelHandleTestFrames.simpleFrame([0x02]))

        let t3 = Task {
            try await f.handle.send(frame: ChannelHandleTestFrames.simpleFrame([0x03]))
        }
        try await Task.sleep(nanoseconds: 10_000_000)

        f.handle.send(nonblocking: ChannelHandleTestFrames.simpleFrame([0x04]))

        // 아직은 쓰기가 일어나지 않았어야 한다
        #expect(f.stream.writtenFrames.isEmpty)

        try await f.handle.activate()
        try await t1.value
        try await t3.value

        let written = f.stream.writtenFrames
        #expect(written.count == 4)
        #expect(written[0].data == Data([0x01]))
        #expect(written[1].data == Data([0x02]))
        #expect(written[2].data == Data([0x03]))
        #expect(written[3].data == Data([0x04]))

        try await f.handle.close()
    }

    @Test("버퍼링된 async send는 activate 후에야 return된다")
    func bufferedAsyncSend_returnsAfterActivate() async throws {
        let f = ChannelHandleFixture()

        let sendTask = Task { () -> Bool in
            try await f.handle.send(frame: ChannelHandleTestFrames.simpleFrame([0x99]))
            return true
        }

        // activate 전에는 task가 끝나있으면 안 된다
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(sendTask.isCancelled == false)
        #expect(f.stream.writtenFrames.isEmpty)

        try await f.handle.activate()
        let didReturn = try await sendTask.value
        #expect(didReturn == true)
        #expect(f.stream.writtenFrames.count == 1)

        try await f.handle.close()
    }

    // MARK: - Close semantics

    @Test("activate 전에 close()하면 pending async send는 channelClosed로 실패한다")
    func close_beforeActivate_failsPendingAsyncSendsWithChannelClosed() async throws {
        let f = ChannelHandleFixture()

        let sendTask = Task { () -> Result<Void, Error> in
            do {
                try await f.handle.send(frame: ChannelHandleTestFrames.simpleFrame([0xCC]))
                return .success(())
            } catch {
                return .failure(error)
            }
        }

        // buffered 상태임을 보장
        try await Task.sleep(nanoseconds: 20_000_000)

        try await f.handle.close()

        let result = await sendTask.value
        switch result {
        case .success:
            Issue.record("pre-activate buffered send가 close() 후에도 성공하면 안 된다")
        case .failure(let err):
            if case ChannelError.channelClosed = err {
                // OK
            } else {
                Issue.record("예상한 ChannelError.channelClosed가 아닌 에러: \(err)")
            }
        }
        // stream에는 아무것도 쓰이지 않았어야 한다
        #expect(f.stream.writtenFrames.isEmpty)
    }

    @Test("activate 전에 close()하면 pending nonblocking send는 조용히 drop된다")
    func close_beforeActivate_dropsPendingNonblockingSends() async throws {
        let f = ChannelHandleFixture()

        f.handle.send(nonblocking: ChannelHandleTestFrames.simpleFrame([0xDD]))
        try await f.handle.close()

        // 기록된 프레임이 없어야 한다
        #expect(f.stream.writtenFrames.isEmpty)
    }

    @Test("close()는 idempotent하다")
    func close_isIdempotent() async throws {
        let f = ChannelHandleFixture()
        try await f.handle.close()
        try await f.handle.close()
    }

    @Test("closed 상태의 send(frame:)은 channelClosed를 throw한다")
    func sendFrame_afterClose_throwsChannelClosed() async throws {
        let f = ChannelHandleFixture()
        try await f.handle.close()

        do {
            try await f.handle.send(frame: ChannelHandleTestFrames.simpleFrame())
            Issue.record("close 이후 send가 성공하면 안 된다")
        } catch ChannelError.channelClosed {
            // OK
        } catch {
            Issue.record("예상한 ChannelError.channelClosed가 아닌 에러: \(error)")
        }
    }

    @Test("closed 상태의 nonblocking send는 조용히 drop된다")
    func sendNonblocking_afterClose_silentlyDropped() async throws {
        let f = ChannelHandleFixture()
        try await f.handle.close()

        f.handle.send(nonblocking: ChannelHandleTestFrames.simpleFrame())
        #expect(f.stream.writtenFrames.isEmpty)
    }

    // MARK: - Events stream ordering

    @Test("활성화 직후 events는 .ready를 1회 yield한다")
    func events_yieldsReadyOnceAfterActivate() async throws {
        let f = ChannelHandleFixture()

        let iter = Task { () -> ChannelEvent? in
            var it = f.handle.events.makeAsyncIterator()
            return await it.next()
        }

        try await f.handle.activate()

        let first = try #require(await iter.value)
        switch first {
        case .ready:
            break
        default:
            Issue.record("첫 이벤트가 .ready 가 아님: \(first)")
        }

        try await f.handle.close()
    }

    @Test("활성화 이후 주입한 프레임은 .frameReceived로 도착 순서대로 전달된다")
    func events_yieldsFrameReceivedInStreamArrivalOrder() async throws {
        let f = ChannelHandleFixture()

        let collectedTask = Task { () -> [SiriusFrame] in
            var collected: [SiriusFrame] = []
            for await event in f.handle.events {
                switch event {
                case .ready:
                    continue
                case .frameReceived(let frame):
                    collected.append(frame)
                    if collected.count == 3 { return collected }
                case .closed, .error:
                    return collected
                }
            }
            return collected
        }

        try await f.handle.activate()

        f.stream.injectFrame(SiriusFrame(opcode: .ping, length: 1, data: Data([0x01])))
        f.stream.injectFrame(SiriusFrame(opcode: .ping, length: 1, data: Data([0x02])))
        f.stream.injectFrame(SiriusFrame(opcode: .ping, length: 1, data: Data([0x03])))

        let frames = await collectedTask.value
        #expect(frames.count == 3)
        #expect(frames[0].data == Data([0x01]))
        #expect(frames[1].data == Data([0x02]))
        #expect(frames[2].data == Data([0x03]))

        try await f.handle.close()
    }

    @Test("activate 이전에 도착한 프레임도 유실 없이 .ready 이후에 순서대로 전달된다")
    func events_bufferedFramesBeforeActivate_deliveredAfterReady() async throws {
        let f = ChannelHandleFixture()

        // stream.events 는 AsyncStream(.unbounded) 이므로 pre-activate 주입도 버퍼링된다
        f.stream.injectFrame(SiriusFrame(opcode: .ping, length: 1, data: Data([0xA1])))
        f.stream.injectFrame(SiriusFrame(opcode: .ping, length: 1, data: Data([0xA2])))

        let collectedTask = Task { () -> [ChannelEvent] in
            var collected: [ChannelEvent] = []
            for await event in f.handle.events {
                collected.append(event)
                if collected.count == 3 { return collected }
            }
            return collected
        }

        try await f.handle.activate()

        let events = await collectedTask.value
        #expect(events.count == 3)

        // 첫번째는 .ready 여야 한다
        if case .ready = events[0] {
            // OK
        } else {
            Issue.record("첫 이벤트가 .ready 가 아님: \(events[0])")
        }

        // 다음 둘은 주입 순서와 동일해야 한다
        if case .frameReceived(let f1) = events[1] {
            #expect(f1.data == Data([0xA1]))
        } else {
            Issue.record("두번째 이벤트가 .frameReceived 가 아님: \(events[1])")
        }
        if case .frameReceived(let f2) = events[2] {
            #expect(f2.data == Data([0xA2]))
        } else {
            Issue.record("세번째 이벤트가 .frameReceived 가 아님: \(events[2])")
        }

        try await f.handle.close()
    }

    @Test("stream close 시 events는 .closed를 yield하고 종료된다")
    func events_yieldsClosedOnStreamClose() async throws {
        let f = ChannelHandleFixture()

        let collectedTask = Task { () -> [ChannelEvent] in
            var collected: [ChannelEvent] = []
            for await event in f.handle.events {
                collected.append(event)
            }
            return collected
        }

        try await f.handle.activate()
        try await Task.sleep(nanoseconds: 10_000_000)

        f.stream.injectClose()

        let events = await collectedTask.value
        #expect(events.contains { if case .closed = $0 { return true } else { return false } })
    }

    @Test("stream error 시 events는 .error를 yield하고 종료된다")
    func events_yieldsErrorOnStreamError() async throws {
        let f = ChannelHandleFixture()

        let collectedTask = Task { () -> [ChannelEvent] in
            var collected: [ChannelEvent] = []
            for await event in f.handle.events {
                collected.append(event)
            }
            return collected
        }

        try await f.handle.activate()
        try await Task.sleep(nanoseconds: 10_000_000)

        f.stream.injectError(StreamError.aborted)

        let events = await collectedTask.value
        #expect(events.contains { if case .error = $0 { return true } else { return false } })
    }

    @Test("activate 없이 close하면 .ready 없이 .closed만 나오고 종료된다")
    func events_closeBeforeActivate_yieldsClosedWithoutReady() async throws {
        let f = ChannelHandleFixture()

        let collectedTask = Task { () -> [ChannelEvent] in
            var collected: [ChannelEvent] = []
            for await event in f.handle.events {
                collected.append(event)
            }
            return collected
        }

        try await Task.sleep(nanoseconds: 10_000_000)
        try await f.handle.close()

        let events = await collectedTask.value

        // .ready 는 절대 나오면 안 된다
        let hasReady = events.contains { if case .ready = $0 { return true } else { return false } }
        #expect(hasReady == false)

        // .closed 는 나와야 한다
        let hasClosed = events.contains { if case .closed = $0 { return true } else { return false } }
        #expect(hasClosed == true)
    }

    // MARK: - Lifecycle Delegate

    @Test("stream close 시 lifecycleDelegate.channelDidClose가 호출된다")
    func lifecycleDelegate_channelDidCloseCalledOnStreamClose() async throws {
        let f = ChannelHandleFixture()
        let delegate = ObservingLifecycleDelegate()
        f.handle.lifecycleDelegate = delegate

        try await f.handle.activate()
        try await Task.sleep(nanoseconds: 10_000_000)
        f.stream.injectClose()

        // delegate 호출까지 이벤트 루프 처리를 기다린다
        for _ in 0..<50 {
            if !delegate.didCloseChannels.isEmpty { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(delegate.didCloseChannels.contains(f.handle.identifier))
    }

    @Test("stream error 시 lifecycleDelegate.channel(_:didEncounterError:)가 호출된다")
    func lifecycleDelegate_didEncounterErrorCalledOnStreamError() async throws {
        let f = ChannelHandleFixture()
        let delegate = ObservingLifecycleDelegate()
        f.handle.lifecycleDelegate = delegate

        try await f.handle.activate()
        try await Task.sleep(nanoseconds: 10_000_000)
        f.stream.injectError(StreamError.aborted)

        for _ in 0..<50 {
            if !delegate.encounteredErrors.isEmpty { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(delegate.encounteredErrors.contains { $0.0 == f.handle.identifier })
    }

    // MARK: - Fast-path race (best-effort)

    @Test("concurrent activate + send 는 hang 없이 호출 개수만큼 기록된다")
    func concurrentActivateAndSend_preservesCount_bestEffort() async throws {
        let f = ChannelHandleFixture()
        let count = 20

        let sendTasks: [Task<Void, Error>] = (0..<count).map { i in
            Task {
                try await f.handle.send(frame: ChannelHandleTestFrames.simpleFrame([UInt8(i)]))
            }
        }

        let activateTask = Task {
            try await f.handle.activate()
        }

        for task in sendTasks { try await task.value }
        try await activateTask.value

        #expect(f.stream.writtenFrames.count == count)

        try await f.handle.close()
    }
}
