//
//  HIDIOGCKeyboard.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/18/25.
//

import Carbon
import Foundation

import Combine
import GameController

import SiriusKitClient

extension HIDIOVirtualDeviceIdentifier {
    /// GameController.framework를 사용한 키보드 가상 디바이스.
    static let gcKeyboard = Self(rawValue: UUID(uuidString: "D75DDF89-09E5-4BFC-B28A-64896249C401")!)
}

@MainActor
final class HIDIOGCKeyboard: HIDIOVirtualDevice {
    nonisolated(unsafe) private static var _shared: HIDIOGCKeyboard? = nil

    static func shared() -> HIDIOGCKeyboard {
        if _shared == nil {
            let shared = HIDIOGCKeyboard()
            shared.setup()

            _shared = shared
        }

        return _shared!
    }

    static let kind: HIDIOVirtualDeviceKind = .keyboard
    static let identifier: HIDIOVirtualDeviceIdentifier = .gcKeyboard

    var localIdentifier: String? { nil }

    private var cancellables: Set<AnyCancellable> = []

    private var keyboard: GCKeyboard? {
        willSet {
            if newValue == nil {
                self.destroyKeyboardInputHandler()
            }
        }
        didSet {
            if keyboard != nil {
                self.setupKeyboardInputHandler()
            }
        }
    }

    private weak var controller: HIDIOController?

    /// keyDown 을 송신했지만 아직 keyUp 을 송신하지 않은 키들.
    /// Control+Space (IM 전환), Command+Shift+4 (스크린샷) 등 시스템이 가로채는
    /// 단축키는 keyUp 이 GameController 로 전달되지 않아 stuck key 가 발생하므로,
    /// 이 집합을 GCKeyboard 의 실제 button state 와 주기적으로 reconcile 한다.
    private var pressedKeys: Set<GCKeyCode> = []

    private var reconcileTask: Task<Void, Never>?

    private static let reconcileInterval: UInt64 = 250_000_000  // 100ms

    init() {

    }

    deinit {
        // HIDIOGCKeyboard 는 @MainActor 이지만 deinit 은 nonisolated.
        // destroyKeyboardInputHandler / disconnect 은 MainActor-isolated 이므로
        // deinit 에서 직접 호출할 수 없다. 정상 경로에서는 상위가 disconnect() 를
        // 먼저 호출한다는 전제 하에 별도 cleanup 을 생략한다.
    }

    fileprivate func setup() {
        NotificationCenter.default.publisher(for: .GCKeyboardDidConnect)
            .compactMap { $0.object as? GCKeyboard }
            .sink { [weak self] keyboard in
                Task { @MainActor [weak self] in
                    self?.keyboard = keyboard
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .GCKeyboardDidDisconnect)
            .compactMap { $0.object as? GCKeyboard }
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.keyboard = nil
                }
            }
            .store(in: &cancellables)
    }


    fileprivate func setupKeyboardInputHandler() {
        guard self.controller != nil else {
            return
        }

        if keyboard == nil {
            self.keyboard = GCKeyboard.coalesced
        }

        self.keyboard?.keyboardInput?.keyChangedHandler = { [weak self] keyboard, key, keyCode, pressed in
            // GCKeyboard.keyChangedHandler 는 일반적으로 main queue 에서 delivery 되지만
            // 문서상 격리 보장이 없으므로 명시적으로 MainActor 에 진입한다.
            Task { @MainActor [weak self] in
                self?.handleKeyChange(keyCode: keyCode, pressed: pressed)
            }
        }

        self.startReconcileTimer()
    }

    fileprivate func destroyKeyboardInputHandler() {
        self.stopReconcileTimer()
        self.releaseAllPressedKeys()
        self.keyboard?.keyboardInput?.keyChangedHandler = nil
    }

    private func handleKeyChange(keyCode: GCKeyCode, pressed: Bool) {
        guard let controller = self.controller else {
            return
        }
        
        // 시스템이 가로챈 단축키로 인해 keyUp 이 누락된 다른 키들을 즉시 회수한다.
        self.reconcilePressedKeys()

        if pressed {
            if pressedKeys.insert(keyCode).inserted {
                let linuxKeyCode = LinuxKeycode.from(gameController: keyCode)
                controller.keyDown(keyCode: linuxKeyCode)
            }
        } else {
            if pressedKeys.remove(keyCode) != nil {
                let linuxKeyCode = LinuxKeycode.from(gameController: keyCode)
                controller.keyUp(keyCode: linuxKeyCode)
            }
        }
    }

    /// `pressedKeys` 와 GCKeyboard 의 실제 button state 를 비교해서,
    /// 우리는 눌린 것으로 추적 중이지만 실제로는 떼어진 키에 대해 keyUp 을 송신한다.
    private func reconcilePressedKeys() {
        guard let controller = self.controller,
              let keyboardInput = self.keyboard?.keyboardInput else {
            return
        }
        
        var releasedKeys: [GCKeyCode] = []
        for keyCode in pressedKeys {
            
            switch keyCode {
            case .rightShift:
                if !NSEvent.modifierFlags.contains(.shift) {
                    releasedKeys.append(keyCode)
                }
            case .rightAlt:
                if !NSEvent.modifierFlags.contains(.option) {
                    releasedKeys.append(keyCode)
                }
            case .rightControl:
                if !NSEvent.modifierFlags.contains(.control) {
                    releasedKeys.append(keyCode)
                }
            case .rightGUI:
                if !NSEvent.modifierFlags.contains(.command) {
                    releasedKeys.append(keyCode)
                }
            default:
                guard let cgKeyCode = LinuxKeycode.from(gameController: keyCode).toCarbonKeycode else {
                    continue
                }
                
                let pressed = CGEventSource.keyState(.combinedSessionState, key: UInt16(cgKeyCode))
                if !pressed {
                    releasedKeys.append(keyCode)
                }
            }
        }

        for keyCode in releasedKeys {
            pressedKeys.remove(keyCode)
            let linuxKeyCode = LinuxKeycode.from(gameController: keyCode)
            controller.keyUp(keyCode: linuxKeyCode)
        }
    }

    private func releaseAllPressedKeys() {
        if let controller = self.controller {
            for keyCode in pressedKeys {
                let linuxKeyCode = LinuxKeycode.from(gameController: keyCode)
                controller.keyUp(keyCode: linuxKeyCode)
            }
        }
        pressedKeys.removeAll()
    }

    private func startReconcileTimer() {
        reconcileTask?.cancel()
        reconcileTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.reconcileInterval)
                guard !Task.isCancelled else { return }
                self?.reconcilePressedKeys()
            }
        }
    }

    private func stopReconcileTimer() {
        reconcileTask?.cancel()
        reconcileTask = nil
    }

    func connect(to controller: HIDIOController) {
        self.controller = controller
        self.setupKeyboardInputHandler()
    }

    func disconnect() {
        // destroyKeyboardInputHandler 안에서 stuck key 를 회수할 수 있도록
        // controller 참조를 먼저 해제하지 않는다.
        self.destroyKeyboardInputHandler()
        self.controller = nil
    }
}
