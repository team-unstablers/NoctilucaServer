//
//  HIDIOCocoaEventTapKeyboard.swift
//  NoctilucaClient
//
//  Created by Codex on 12/21/25.
//

#if os(macOS)

import Foundation
import Carbon
import CoreGraphics

import SiriusKitClient

private func HIDIOCocoaEventTapKeyboardCallback(_ proxy: CGEventTapProxy, _ eventType: CGEventType, _ event: CGEvent, _ userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    
    guard let userInfo else {
        return Unmanaged.passUnretained(event)
    }
    
    let instance = HIDIOCocoaEventTapKeyboard.fromCInteropHandle(userInfo)
    return instance.handleEvent(proxy: proxy, type: eventType, event: event)
}

extension HIDIOVirtualDeviceIdentifier {
    /// Cocoa Event Tap을 사용한 키보드 가상 디바이스. (macOS 전용)
    static let cocoaEventTapKeyboard = Self(rawValue: UUID(uuidString: "AFB5D1BE-0126-4C92-96AE-83BB2E2B8A88")!)
}

final class HIDIOCocoaEventTapKeyboard: HIDIOVirtualDevice, CInteropHandle {
    private static let logger = NoctilucaLogger(category: "HIDIOCocoaEventTapKeyboard")
    nonisolated(unsafe) private static var _shared: HIDIOCocoaEventTapKeyboard?

    /// 이 키보드 인스턴스를 취득하려고 시도합니다.
    @MainActor
    static func acquire(force: Bool = false) throws -> HIDIOCocoaEventTapKeyboard {
        if _shared == nil {
            let instance = try HIDIOCocoaEventTapKeyboard()

            _shared = instance
            return instance
        }

        guard let instance = _shared else {
            logger.error("Inconsistent state: _shared is nil after checking nil.")
            throw HIDIOVirtualDeviceError.initializationFailed(nil)
        }

        instance.disconnect()
        return instance
    }

    static let kind: HIDIOVirtualDeviceKind = .keyboard
    static let identifier: HIDIOVirtualDeviceIdentifier = .cocoaEventTapKeyboard

    /// CGEventTap 콜백은 전용 run loop thread 에서 호출되므로 controller 참조를
    /// MainActor 경계 없이 읽어야 한다. 쓰기(`connect`/`disconnect`) 는 MainActor
    /// 에서만 일어나고, 쓰기 시점에 `stopEventTap()` 이 먼저 호출되어 이후 콜백이
    /// 중단되므로 실질적인 race 는 없다. Rule I 예외 3 (외부 run loop 스레드 경유
    /// 콜백) 으로 문서화 대상.
    nonisolated(unsafe) private weak var controller: HIDIOController?

    private var eventTap: CFMachPort!
    private var eventTapRunLoopSource: CFRunLoopSource!

    nonisolated(unsafe) private var eventTapThread: Thread?
    nonisolated(unsafe) private var eventTapRunLoop: CFRunLoop?

    var localIdentifier: String? { nil }


    private init() throws {
        let eventMask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)   |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue) |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)
        )

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: HIDIOCocoaEventTapKeyboardCallback,
            userInfo: self.asCInteropHandle
        ),
              let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        else {
            throw HIDIOVirtualDeviceError.initializationFailed(nil)
        }
        
        self.eventTap = eventTap
        self.eventTapRunLoopSource = runLoopSource
    }

    deinit {
        // disconnect() 는 MainActor-isolated 이므로 nonisolated deinit 에서
        // 직접 호출할 수 없다. 대신 event tap 자체를 정리해 dangling thread 를 막는다.
        // controller 참조는 weak 이므로 자연스럽게 해제된다.
        stopEventTap()
    }

    @MainActor
    func connect(to controller: HIDIOController) {
        self.controller = controller
        startEventTapIfNeeded()
    }

    @MainActor
    func disconnect() {
        stopEventTap()
        controller = nil
    }

    /// NOTE: 이걸 호출하기 시작하는 순간부터 키보드 입력은 잠깁니다!!
    private func startEventTapIfNeeded() {
        guard eventTapThread == nil else {
            return
        }
        
        let eventTapThread = Thread {
            self.eventTapThreadMain()
        }
        
        self.eventTapThread = eventTapThread
        eventTapThread.start()
    }

    /// 이걸 호출하는 순간부터 키보드 입력이 풀립니다!!
    private func stopEventTap() {
        guard let runLoop = eventTapRunLoop else {
            return
        }
        CGEvent.tapEnable(tap: eventTap, enable: false)
        CFRunLoopStop(runLoop)
    }

    fileprivate func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            CGEvent.tapEnable(tap: eventTap, enable: true)
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp, .flagsChanged:
            break
        default:
            return Unmanaged.passUnretained(event)
        }

        if let keyEvent = buildKeyEvent(from: event, type: type) {
            dispatchKeyEvent(keyEvent)
        }

        return nil
    }

    private struct KeyEvent {
        let keyCode: LinuxKeycode
        let isDown: Bool
        // TODO: add timestamp, flags, modifiers if needed
    }

    private func buildKeyEvent(from event: CGEvent, type: CGEventType) -> KeyEvent? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let linuxKeycode = LinuxKeycode.from(carbon: Int(keyCode))

        guard linuxKeycode != .KEY_UNKNOWN else {
            return nil
        }

        switch type {
        case .keyDown:
            return KeyEvent(keyCode: linuxKeycode, isDown: true)
        case .keyUp:
            return KeyEvent(keyCode: linuxKeycode, isDown: false)
        case .flagsChanged:
            guard let isDown = isModifierDown(keyCode: keyCode, flags: event.flags) else {
                return nil
            }
            return KeyEvent(keyCode: linuxKeycode, isDown: isDown)
        default:
            return nil
        }
    }

    private func isModifierDown(keyCode: CGKeyCode, flags: CGEventFlags) -> Bool? {
        switch Int(keyCode) {
        case kVK_Shift, kVK_RightShift:
            return flags.contains(.maskShift)
        case kVK_Control, kVK_RightControl:
            return flags.contains(.maskControl)
        case kVK_Option, kVK_RightOption:
            return flags.contains(.maskAlternate)
        case kVK_Command, kVK_RightCommand:
            return flags.contains(.maskCommand)
        case kVK_CapsLock:
            return flags.contains(.maskAlphaShift)
        default:
            return nil
        }
    }

    private func dispatchKeyEvent(_ event: KeyEvent) {
        // CGEventTap 콜백은 전용 run loop thread 에서 호출된다.
        // HIDIOController 는 @MainActor 로 격리되어 있으므로 MainActor 진입 필요.
        let target = controller
        guard let target else {
            return
        }

        Task { @MainActor [weak target] in
            guard let target else { return }
            if event.isDown {
                target.keyDown(keyCode: event.keyCode)
            } else {
                target.keyUp(keyCode: event.keyCode)
            }
        }
    }
}

extension HIDIOCocoaEventTapKeyboard {
    func eventTapThreadMain() {
        guard let eventTapRunLoop = CFRunLoopGetCurrent() else {
            Self.logger.error("Failed to get current run loop for event tap thread.")
            return
        }
        
        CFRunLoopAddSource(eventTapRunLoop, eventTapRunLoopSource, .commonModes)
        defer {
            CFRunLoopRemoveSource(eventTapRunLoop, eventTapRunLoopSource, .commonModes)
        }
        
        self.eventTapRunLoop = eventTapRunLoop
        defer {
            self.eventTapRunLoop = nil
            self.eventTapThread = nil
        }

        CGEvent.tapEnable(tap: eventTap, enable: true)
        CFRunLoopRun()
        CGEvent.tapEnable(tap: eventTap, enable: false)
    }
}

#endif
