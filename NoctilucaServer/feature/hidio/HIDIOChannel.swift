//
//  HIDIOChannel.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import SiriusKit
import NoctilucaPluginKit

final class HIDIOChannel: Channel, ChannelEventConsumer {
    private static let defaultServiceClass: ServiceClass = .userInput

    let handle: ChannelHandle

    private let logger = NoctilucaLogger(category: "HIDIOChannel")
    private let eventInjector: EventInjector
    private let state: HIDIOChannelState

    // ~Copyable CompatBridge; init 마지막 대입 후 수정 없음. (Rule I 패턴 2)
    nonisolated(unsafe) private var channelEventCompatBridge:
        ChannelEventCompatBridge<HIDIOChannel>!

    init(handle: ChannelHandle) {
        self.handle = handle
        assert(handle.direction == .remote,
               "HIDIOChannel must be opened from remote side")

        self.eventInjector = EventInjector()
        self.state = HIDIOChannelState()

        // EventInjector 는 actor 로 승격되어 prepare() 가 async throws 가 되었다.
        // init 에서는 Task 로 기동만 하고 결과 로깅은 내부에서 수행.
        let injector = self.eventInjector
        let logger = self.logger
        Task {
            do {
                try await injector.prepare()
            } catch {
                logger.error("failed to prepare event injector: \(error.localizedDescription)")
            }
        }

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

        // Handle HIDIO specific frames here
        guard frame.opcode == .hidioPacket else {
            throw ChannelError.invalidFrame
        }

        let hidioPacket = try HIDIOPacket.fromProtobufBytes(frame.data)

        for event in hidioPacket.events {
            switch event {
            case is RawEvent:
                // not implemented
                break
            case is KeyboardSetupEvent:
                await state.updateHacks(from: event as! KeyboardSetupEvent)
            case is KeyboardEvent:
                await self.inject(keyboardEvent: event as! KeyboardEvent)
            case is MouseMoveEvent:
                await self.eventInjector.post(mouseMoveEvent: event as! MouseMoveEvent)
            case is MouseButtonEvent:
                await self.eventInjector.post(mouseButtonEvent: event as! MouseButtonEvent)
            case is MouseWheelEvent:
                await self.eventInjector.post(mouseWheelEvent: event as! MouseWheelEvent)
            default:
                break
            }
        }
    }

    func handleError(error: any Error) async {
        await eventInjector.resetKeyboardState()
    }

    func handleStreamClose() async {
        await eventInjector.resetKeyboardState()
    }

    // MARK: - Helpers

    private func inject(keyboardEvent: KeyboardEvent) async {
        switch keyboardEvent.eventType {
        case .ucs4:
            await eventInjector.postUcs4Input(keyboardEvent.keyCode)
        case .keyDown, .keyUp:
            await injectNormalKey(keyboardEvent)
        default:
            logger.warning("unhandled keyboard event type: \(keyboardEvent.eventType)")
        }
    }

    private func injectNormalKey(_ event: KeyboardEvent) async {
        var keyCode = NoctilucaPluginKit.LinuxKeycode(rawValue: UInt16(event.keyCode))

        // HIDIOChannelState 에서 해당 키에 관심 있는 hack 들만 스냅샷으로 받아온다.
        let hacks = await state.evaluatedHacks(for: keyCode)

        for hack in hacks {
            let decision = switch event.eventType {
            case .keyDown:
                await hack.onKeyDown(keyCode)
            case .keyUp:
                await hack.onKeyUp(keyCode)
            default:
                await hack.onKeyDown(keyCode)
            }

            if case .modify(let modified) = decision {
                keyCode = modified
            } else if case .stop = decision {
                break
            }
        }

        guard let carbonKeyCode = LinuxKeycode(rawValue: UInt16(keyCode.rawValue)).toCarbonKeycode else {
            logger.warning("failed to map linux keycode \(event.keyCode) to carbon keycode")
            return
        }

        switch event.eventType {
        case .keyDown:
            await eventInjector.postKeyDown(carbonKeyCode)
        case .keyUp:
            await eventInjector.postKeyUp(carbonKeyCode)
        default:
            break
        }
    }
}

/// HIDIO 채널의 가변 상태 격리 actor.
///
/// HIDIO 는 서버 쪽에서 **수신 전용**이고 `ChannelEventCompatBridge` 의 단일
/// `Task.detached` 에서 `handleFrame` 이 순차 호출되므로, 이론상 별도의 격리가
/// 없어도 동시 접근이 일어나지 않는다. 그러나 Swift 6 strict concurrency 에서는
/// 채널 본체가 Sendable 이어야 하므로, 가변 상태를 별도 actor 로 분리해 격리한다
/// (문서 Rule G).
actor HIDIOChannelState {
    private var keyboardHacks: [KeyboardHackPluginV1] = []

    func updateHacks(from event: KeyboardSetupEvent) async {
        let snapshot = await HIDIOKeyboardHackRegistry.shared.snapshot()
        self.keyboardHacks.removeAll()

        for hack in event.hacks {
            if let plugin = snapshot[hack.identifier] {
                self.keyboardHacks.append(plugin)
            }
        }
    }

    func evaluatedHacks(for keyCode: NoctilucaPluginKit.LinuxKeycode) -> [KeyboardHackPluginV1] {
        keyboardHacks.filter { type(of: $0).desiredKeyEvents.contains(keyCode) }
    }
}
