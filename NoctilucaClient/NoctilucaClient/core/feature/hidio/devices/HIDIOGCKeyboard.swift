//
//  HIDIOGCKeyboard.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/18/25.
//

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
                guard let controller = self?.controller else {
                    return
                }

                let linuxKeyCode = LinuxKeycode.from(gameController: keyCode)

                if pressed {
                    controller.keyDown(keyCode: linuxKeyCode)
                } else {
                    controller.keyUp(keyCode: linuxKeyCode)
                }
            }
        }
    }

    fileprivate func destroyKeyboardInputHandler() {
        self.keyboard?.keyboardInput?.keyChangedHandler = nil
    }

    func connect(to controller: HIDIOController) {
        self.controller = controller
        self.setupKeyboardInputHandler()
    }

    func disconnect() {
        self.controller = nil
        self.destroyKeyboardInputHandler()
    }
}
