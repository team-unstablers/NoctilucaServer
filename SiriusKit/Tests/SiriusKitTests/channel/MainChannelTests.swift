//
//  MainChannelTests.swift
//  SiriusKitTests
//
//  MainChannel의 프레임 디스패치 동작을 단위 테스트 수준에서 검증한다.
//  (ServerMainChannelTests는 ClientSession 통합 경로를 통한 고차 테스트이지만,
//  이 파일은 Channel/ChannelHandleImpl 프리미티브를 직접 조립해서
//  프로토콜 처리 로직만 격리 검증한다.)
//

import Testing
import Foundation

@testable import SiriusKitCore
@testable import SiriusKit

@Suite("MainChannel Frame Dispatch Tests")
struct MainChannelTests {

    // MARK: - Fixture

    private struct Fixture {
        let session: MockSiriusSession
        let stream: MockStream
        let handle: ChannelHandleImpl
        let mainChannel: MainChannel

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
            mainChannel = MainChannel(handle: handle)
        }

        func activate() async throws {
            try await handle.activate()
        }

        func close() async throws {
            try await handle.close()
        }
    }

    /// MainChannel.events 에서 predicate 와 매칭되는 첫 이벤트를 반환한다.
    /// timeoutSeconds 안에 도착하지 않으면 nil 을 반환한다.
    private func firstEvent(
        from channel: MainChannel,
        matching predicate: @Sendable @escaping (MainChannelEvent) -> Bool,
        timeoutSeconds: TimeInterval = 2
    ) async -> MainChannelEvent? {
        await withTaskGroup(of: MainChannelEvent?.self) { group in
            group.addTask {
                for await event in channel.events {
                    if predicate(event) { return event }
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
                return nil
            }
            let first = (await group.next()) ?? nil
            group.cancelAll()
            return first
        }
    }

    // MARK: - Receiving frames (server-side; receives ClientHello/AuthRequest/etc.)

    @Test("clientHello 프레임 수신 시 .receivedClientHello 이벤트가 emit된다")
    func receivedClientHelloFrame_emitsEvent() async throws {
        let f = Fixture()
        try await f.activate()

        f.stream.injectFrame(try FrameBuilder.clientHelloFrame(
            protocolVersion: .v1_0,
            agentName: "test-agent"
        ))

        let event = await firstEvent(from: f.mainChannel) {
            if case .receivedClientHello = $0 { return true } else { return false }
        }

        if case .receivedClientHello(let hello) = event {
            #expect(hello.agentName == "test-agent")
        } else {
            Issue.record("expected .receivedClientHello, got \(String(describing: event))")
        }

        try await f.close()
    }

    @Test("serverHello 프레임 수신 시 .receivedServerHello 이벤트가 emit된다")
    func receivedServerHelloFrame_emitsEvent() async throws {
        let f = Fixture()
        try await f.activate()

        f.stream.injectFrame(try FrameBuilder.serverHelloFrame(
            supportedFeatures: [SiriusFeature.hidio.rawValue],
            serverName: "test-server"
        ))

        let event = await firstEvent(from: f.mainChannel) {
            if case .receivedServerHello = $0 { return true } else { return false }
        }

        if case .receivedServerHello(let hello) = event {
            #expect(hello.serverName == "test-server")
        } else {
            Issue.record("expected .receivedServerHello, got \(String(describing: event))")
        }

        try await f.close()
    }

    @Test("authChallenge 프레임 수신 시 .receivedAuthChallenge 이벤트가 emit된다")
    func receivedAuthChallengeFrame_emitsEvent() async throws {
        let f = Fixture()
        try await f.activate()

        f.stream.injectFrame(try FrameBuilder.authChallengeFrame(
            acceptedMethods: ["password"],
            nonce: Data([0xDE, 0xAD, 0xBE, 0xEF])
        ))

        let event = await firstEvent(from: f.mainChannel) {
            if case .receivedAuthChallenge = $0 { return true } else { return false }
        }

        if case .receivedAuthChallenge(let challenge) = event {
            #expect(challenge.acceptedMethods == ["password"])
            #expect(challenge.nonce == Data([0xDE, 0xAD, 0xBE, 0xEF]))
        } else {
            Issue.record("expected .receivedAuthChallenge, got \(String(describing: event))")
        }

        try await f.close()
    }

    @Test("authRequest 프레임 수신 시 .receivedAuthRequest 이벤트가 emit된다")
    func receivedAuthRequestFrame_emitsEvent() async throws {
        let f = Fixture()
        try await f.activate()

        f.stream.injectFrame(try FrameBuilder.authRequestFrame(
            method: "password",
            nonce: Data([0x01, 0x02]),
            payload: Data([0x03, 0x04])
        ))

        let event = await firstEvent(from: f.mainChannel) {
            if case .receivedAuthRequest = $0 { return true } else { return false }
        }

        if case .receivedAuthRequest(let request) = event {
            #expect(request.method == "password")
        } else {
            Issue.record("expected .receivedAuthRequest, got \(String(describing: event))")
        }

        try await f.close()
    }

    @Test("authResponse 프레임 수신 시 .receivedAuthResponse 이벤트가 emit된다")
    func receivedAuthResponseFrame_emitsEvent() async throws {
        let f = Fixture()
        try await f.activate()

        let sessionID = UUID()
        f.stream.injectFrame(try FrameBuilder.authResponseFrame(sessionID: sessionID))

        let event = await firstEvent(from: f.mainChannel) {
            if case .receivedAuthResponse = $0 { return true } else { return false }
        }

        if case .receivedAuthResponse(let response) = event {
            #expect(response.sessionID == sessionID)
        } else {
            Issue.record("expected .receivedAuthResponse, got \(String(describing: event))")
        }

        try await f.close()
    }

    @Test("serverNotice 프레임 수신 시 .receivedServerNotice 이벤트가 emit된다")
    func receivedServerNoticeFrame_emitsEvent() async throws {
        let f = Fixture()
        try await f.activate()

        f.stream.injectFrame(try FrameBuilder.serverNoticeFrame(
            severity: .warning,
            code: 42,
            message: "hi",
            timestamp: 1234
        ))

        let event = await firstEvent(from: f.mainChannel) {
            if case .receivedServerNotice = $0 { return true } else { return false }
        }

        if case .receivedServerNotice(let notice) = event {
            #expect(notice.code == 42)
            #expect(notice.message == "hi")
        } else {
            Issue.record("expected .receivedServerNotice, got \(String(describing: event))")
        }

        try await f.close()
    }

    @Test("goodbye 프레임 수신 시 .receivedGoodbye 이벤트가 emit된다")
    func receivedGoodbyeFrame_emitsEvent() async throws {
        let f = Fixture()
        try await f.activate()

        f.stream.injectFrame(try FrameBuilder.goodbyeFrame(
            code: .successful,
            message: "bye"
        ))

        let event = await firstEvent(from: f.mainChannel) {
            if case .receivedGoodbye = $0 { return true } else { return false }
        }

        if case .receivedGoodbye(let bye) = event {
            #expect(bye.message == "bye")
        } else {
            Issue.record("expected .receivedGoodbye, got \(String(describing: event))")
        }

        try await f.close()
    }

    @Test("ping 프레임 수신 시 .receivedPing 이벤트가 emit된다")
    func receivedPingFrame_emitsReceivedPing() async throws {
        let f = Fixture()
        try await f.activate()

        f.stream.injectFrame(SiriusFrame(opcode: .ping, length: 0, data: Data()))

        let event = await firstEvent(from: f.mainChannel) {
            if case .receivedPing = $0 { return true } else { return false }
        }
        if case .receivedPing = event {
            // OK
        } else {
            Issue.record("expected .receivedPing, got \(String(describing: event))")
        }

        try await f.close()
    }

    @Test("pong 프레임 수신 시 .receivedPong 이벤트가 emit된다")
    func receivedPongFrame_emitsReceivedPong() async throws {
        let f = Fixture()
        try await f.activate()

        f.stream.injectFrame(SiriusFrame(opcode: .pong, length: 0, data: Data()))

        let event = await firstEvent(from: f.mainChannel) {
            if case .receivedPong = $0 { return true } else { return false }
        }
        if case .receivedPong = event {
            // OK
        } else {
            Issue.record("expected .receivedPong, got \(String(describing: event))")
        }

        try await f.close()
    }

    // MARK: - Stream close propagation

    @Test("stream close 시 MainChannel.events 는 종료된다")
    func handleStreamClose_finishesEventsStream() async throws {
        let f = Fixture()
        try await f.activate()

        let drainTask = Task { () -> Bool in
            for await _ in f.mainChannel.events { }
            return true
        }

        // 잠깐 여유 두고 close
        try await Task.sleep(nanoseconds: 20_000_000)
        f.stream.injectClose()

        // events stream이 finish 되어 drain task가 return 해야 한다
        let finished = await withTaskGroup(of: Bool.self) { group in
            group.addTask { (await drainTask.value) }
            group.addTask {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                return false
            }
            let result = await group.next() ?? false
            group.cancelAll()
            return result
        }
        #expect(finished == true)
    }

    // MARK: - sendClientHello delegate to handle

    @Test("sendClientHello 는 handle.send(opcode:message:) 로 위임된다")
    func sendClientHello_delegatesToHandleSend() async throws {
        let f = Fixture()
        try await f.activate()

        try await f.mainChannel.sendClientHello(
            ClientHello(protocolVersion: .v1_0, agentName: "delegate-test")
        )

        let written = f.stream.frames(withOpcode: .clientHello)
        #expect(written.count == 1)

        try await f.close()
    }

    // MARK: - server-role only: sendPong

    @Test("server-role sendPong 호출 시 pong frame이 stream에 기록된다")
    func sendPong_afterActivate_writesPongFrame() async throws {
        let f = Fixture()
        try await f.activate()

        try await f.mainChannel.sendPong()

        let pongs = f.stream.frames(withOpcode: .pong)
        #expect(pongs.count == 1)

        try await f.close()
    }
}
