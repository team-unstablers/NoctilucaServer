//
//  MainChannelClientTests.swift
//  SiriusKitClientTests
//
//  클라이언트 역할 전용 MainChannel API (`sendPing`) 단위 테스트.
//

import Testing
import Foundation

@testable import SiriusKitCore
@testable import SiriusKitClient

@Suite("MainChannel Client-Role Tests")
struct MainChannelClientTests {

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
    }

    @Test("client-role sendPing 호출 시 ping frame이 stream에 기록된다")
    func sendPing_afterActivate_writesPingFrame() async throws {
        let f = Fixture()
        try await f.handle.activate()

        try await f.mainChannel.sendPing()

        let pings = f.stream.frames(withOpcode: .ping)
        #expect(pings.count == 1)

        try await f.handle.close()
    }
}
