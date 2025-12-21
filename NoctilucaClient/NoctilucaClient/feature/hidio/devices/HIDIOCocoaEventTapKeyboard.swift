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

final class HIDIOCocoaEventTapKeyboard: HIDIOVirtualDevice {
    struct ToggleShortcut {
        let keyCode: CGKeyCode
        let requiredFlags: CGEventFlags

        static let `default` = ToggleShortcut(
            keyCode: CGKeyCode(kVK_Escape),
            requiredFlags: [.maskControl, .maskAlternate, .maskCommand]
        )

        func matches(event: CGEvent, type: CGEventType) -> Bool {
            guard type == .keyDown else {
                return false
            }

            let eventKeyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
            guard eventKeyCode == keyCode else {
                return false
            }

            return event.flags.contains(requiredFlags)
        }
    }

    static let kind: HIDIOVirtualDeviceKind = .keyboard

    private let toggleShortcut: ToggleShortcut

    private weak var controller: HIDIOController?
    private let stateLock = NSLock()

    private var captureModeEnabled: Bool = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var thread: Thread?

    var onError: ((Error) -> Void)?
    var onCaptureModeChanged: ((Bool) -> Void)?

    init(toggleShortcut: ToggleShortcut = .default,
         onError: ((Error) -> Void)? = nil,
         onCaptureModeChanged: ((Bool) -> Void)? = nil) {
        self.toggleShortcut = toggleShortcut
        self.onError = onError
        self.onCaptureModeChanged = onCaptureModeChanged
    }

    deinit {
        disconnect()
    }

    func connect(to controller: HIDIOController) {
        self.controller = controller
        startEventTapIfNeeded()
    }

    func disconnect() {
        stopEventTap()
    }

    func setCaptureModeEnabled(_ enabled: Bool) {
        stateLock.lock()
        captureModeEnabled = enabled
        stateLock.unlock()

        onCaptureModeChanged?(enabled)
    }

    func toggleCaptureMode() {
        stateLock.lock()
        captureModeEnabled.toggle()
        let enabled = captureModeEnabled
        stateLock.unlock()

        onCaptureModeChanged?(enabled)
    }

    private func isCaptureModeEnabled() -> Bool {
        stateLock.lock()
        let enabled = captureModeEnabled
        stateLock.unlock()
        return enabled
    }

    private func startEventTapIfNeeded() {
        guard thread == nil else {
            return
        }

        let thread = Thread { [weak self] in
            self?.runEventTapLoop()
        }
        thread.name = "HIDIOCocoaEventTapKeyboard"
        self.thread = thread
        thread.start()
    }

    private func stopEventTap() {
        guard let runLoop else {
            return
        }

        CFRunLoopStop(runLoop)
        thread = nil
    }

    private func runEventTapLoop() {
        let eventMask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.keyUp.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)
                | (1 << CGEventType.tapDisabledByTimeout.rawValue)
                | (1 << CGEventType.tapDisabledByUserInput.rawValue)
        )

        let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: HIDIOCocoaEventTapKeyboard.eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            onError?(HIDIOVirtualDeviceError.initializationFailed(nil))
            return
        }

        self.eventTap = eventTap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        self.runLoop = CFRunLoopGetCurrent()

        if let runLoopSource, let runLoop {
            CFRunLoopAddSource(runLoop, runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
            CFRunLoopRun()
            CFRunLoopRemoveSource(runLoop, runLoopSource, .commonModes)
        }

        self.runLoopSource = nil
        self.eventTap = nil
        self.runLoop = nil
    }

    private static let eventTapCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        let device = Unmanaged<HIDIOCocoaEventTapKeyboard>.fromOpaque(userInfo).takeUnretainedValue()
        return device.handleEvent(proxy: proxy, type: type, event: event)
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp, .flagsChanged:
            break
        default:
            return Unmanaged.passUnretained(event)
        }

        if toggleShortcut.matches(event: event, type: type) {
            toggleCaptureMode()
            return Unmanaged.passUnretained(event)
        }

        if let keyEvent = buildKeyEvent(from: event, type: type) {
            dispatchKeyEvent(keyEvent)
        }

        if isCaptureModeEnabled() {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    private struct KeyEvent {
        let keyCode: LinuxKeycode
        let isDown: Bool
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
        guard let controller else {
            return
        }

        Task {
            if event.isDown {
                try? await controller.keyDown(keyCode: event.keyCode)
            } else {
                try? await controller.keyUp(keyCode: event.keyCode)
            }
        }
    }
}

#endif
