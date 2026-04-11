//
//  HIDIOChannel.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 11/24/25.
//

import SiriusKitClient


final class HIDIOChannel: Channel, ChannelEventConsumer {
    private static let defaultServiceClass: ServiceClass = .userInput

    let handle: ChannelHandle

    // `RemoteSession.HIDIO` 에서 접근하는 공개 let 필드.
    // HIDIOController 는 @MainActor final class 이지만 참조 자체는 Sendable.
    let controller: HIDIOController

    // ~Copyable CompatBridge; init 마지막 대입 후 수정 없음. (Rule I 패턴 2)
    nonisolated(unsafe) private var channelEventCompatBridge:
        ChannelEventCompatBridge<HIDIOChannel>!

    init(handle: ChannelHandle) {
        self.handle = handle
        assert(handle.direction == .local,
               "HIDIOChannel must be opened from client side")

        // HIDIOController 는 @MainActor final class 이지만 init 자체는
        // nonisolated 로 열려 있어 이곳(FeatureProvider 컨텍스트)에서 직접 생성 가능.
        self.controller = HIDIOController(handle: handle)

        self.channelEventCompatBridge =
            ChannelEventCompatBridge(consumer: self, handle: handle)
    }

    // MARK: - ChannelEventConsumer

    func handleChannelReady() async {
        await handle.setServiceClass(Self.defaultServiceClass)
    }

    func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }

        // 클라이언트는 HIDIO 프레임을 수신하지 않는다.
    }

    func handleError(error: any Error) async {
        await MainActor.run { controller.shutdown() }
    }

    func handleStreamClose() async {
        await MainActor.run { controller.shutdown() }
    }
}
