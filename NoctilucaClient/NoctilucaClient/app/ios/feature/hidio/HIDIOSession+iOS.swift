//
//  Untitled.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/6/26.
//

#if os(iOS)
import Foundation
import Combine
import GameController
import UIKit

import SiriusKitClient

extension HIDIOSession {
    class IOSDriver: Driver {
        private let logger = NoctilucaLogger(category: "HIDIOSession.IOSDriver")
        private weak var _session: HIDIOSession?

        private var session: HIDIOSession {
            // Force unwrap is safe here because the lifecycle of Driver is tied to HIDIOSession
            _session!
        }

        private var controller: HIDIOController {
            session.controller
        }

        private var mode: HIDIOSessionMode {
            session.mode
        }

        private var delegate: HIDIOSessionDelegate? {
            session.delegate
        }

        let defaultKeyboard: HIDIOVirtualDevice
        let defaultSubMouse: HIDIOVirtualDevice

        var currentKeyboard: (any HIDIOVirtualDevice)? {
            defaultKeyboard
        }
        var currentMouse: HIDIOVirtualDevice?

        // MARK: - Pointer Input Routing State
        private var pointerInputMode: AppSettings.PointerInputMode = .automatic
        private var isHardwareMouseConnected: Bool = false
        private var isFullScreen: Bool = false
        private var cancellables: Set<AnyCancellable> = []

        required init(_ session: HIDIOSession) {
            self._session = session

            self.defaultKeyboard = HIDIOGCKeyboard.shared()
            self.defaultSubMouse = HIDIOUIKitMouse()
        }

        @MainActor
        func startSession() throws -> HIDIOSessionMode {
            // setupObservers()

            // 초기 상태 설정
            pointerInputMode = SettingsStore.shared.settings.input.pointerInputMode
            isHardwareMouseConnected = !GCMouse.mice().isEmpty
            /*
            isFullScreen = queryIsFullScreen()

            logger.info("startSession: pointerInputMode=\(String(describing: self.pointerInputMode)), hwMouse=\(self.isHardwareMouseConnected), fullScreen=\(self.isFullScreen), idiom=\(DeviceKind.current == .iPad)")
            
            // 초기 모드 결정
            let initialMode = desiredMode()
            logger.info("startSession: initialMode=\(initialMode)")
            try switchMode(to: initialMode, reason: .userInitiated)
             */
            
            controller.connect(defaultKeyboard)
            controller.connect(defaultSubMouse)

            defer {
                delegate?.hidioSession(session, didChangeState: .active)
            }

            return .shared
        }

        @MainActor
        func stopSession() {
            cancellables.removeAll()

            defer {
                delegate?.hidioSession(session, didChangeState: .inactive)
            }

            controller.disconnectAll(kind: .keyboard)
            controller.disconnectAll(kind: .mouse)
            controller.disconnectAll(kind: .pointer)
            controller.resetKeyPressState()
        }

        func activateSession() {
            controller.connect(defaultKeyboard)
            controller.connect(defaultSubMouse)

            /*
            if let mouse = currentMouse {
                controller.connect(mouse)
            }
             */

            /*
            // 전체 화면 상태가 변경되었을 수 있으므로 재평가
            Task { @MainActor in
                refreshFullScreenState()
            }
             */
        }

        func deactivateSession() {
            controller.disconnectAll(kind: .keyboard)

            /*
            if let mouse = currentMouse {
                controller.disconnect(type(of: mouse).identifier)
            }
             */

            controller.resetKeyPressState()
        }

        @MainActor
        func switchMode(to mode: HIDIOSessionMode, reason: HIDIOSessionModeSwitchReason) throws {
            controller.connect(defaultKeyboard)
            controller.connect(defaultSubMouse)
            
            self._session?.rootViewController?.ref.isPointerLocked = false

            if (mode == .shared) {
                /*
                if let mouse = currentMouse {
                    controller.disconnect(type(of: mouse).identifier)
                }

                self.currentMouse = nil
                 */
                
            } /*else if (mode == .limitedExclusive) {
                let mouse = HIDIOGCMouse()
                controller.connect(mouse)

                self.currentMouse = mouse
                
                self._session?.rootViewController?.ref.isPointerLocked = true
            }
               */

            delegate?.hidioSession(session, didSwitchMode: mode, reason: reason)
        }

        @MainActor
        func switchableModes() -> Set<HIDIOSessionMode> {
            var modes: Set<HIDIOSessionMode> = [.shared]

            /*
            if DeviceKind.current == .iPad && isFullScreen {
                modes.insert(.limitedExclusive)
            }
             */

            return modes
        }

        // MARK: - Private: Observer Setup
        /*
        private func setupObservers() {
            // 1. PointerInputMode 설정 변경 관찰
            SettingsStore.shared.$settings
                .compactMap { $0?.input.pointerInputMode }
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] mode in
                    guard let self else { return }
                    self.pointerInputMode = mode
                    Task { @MainActor in
                        self.evaluateDesiredMode()
                    }
                }
                .store(in: &cancellables)

            // 2. GCMouse 연결/해제 감지
            NotificationCenter.default.publisher(for: .GCMouseDidConnect)
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.isHardwareMouseConnected = !GCMouse.mice().isEmpty
                    self.logger.info("Hardware mouse connected (count: \(GCMouse.mice().count))")
                    Task { @MainActor in
                        self.evaluateDesiredMode()
                    }
                }
                .store(in: &cancellables)

            NotificationCenter.default.publisher(for: .GCMouseDidDisconnect)
                .sink { [weak self] _ in
                    guard let self else { return }
                    self.isHardwareMouseConnected = !GCMouse.mice().isEmpty
                    self.logger.info("Hardware mouse disconnected (count: \(GCMouse.mice().count))")
                    Task { @MainActor in
                        self.evaluateDesiredMode()
                    }
                }
                .store(in: &cancellables)

            // 3. 전체 화면 상태 변경 감지
            //    Scene 활성화 시 isFullScreen 재평가 (Stage Manager 전환 등)
            NotificationCenter.default.publisher(for: UIScene.didActivateNotification)
                .sink { [weak self] _ in
                    Task { @MainActor in
                        self?.refreshFullScreenState()
                    }
                }
                .store(in: &cancellables)
        }

        // MARK: - Private: Full Screen Detection

        @MainActor
        private func queryIsFullScreen() -> Bool {
            guard DeviceKind.current == .iPad else {
                return false
            }
            
            // foregroundActive를 우선하되, 없으면 foregroundInactive scene도 확인
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
                    ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            else {
                return false
            }
            
            guard let keyWindow = scene.keyWindow else {
                return false
            }
            
            let screen = scene.screen
            return screen.bounds == keyWindow.frame
        }

        @MainActor
        private func refreshFullScreenState() {
            let newState = queryIsFullScreen()
            guard newState != isFullScreen else { return }

            isFullScreen = newState
            logger.info("Full screen state changed: \(self.isFullScreen)")
            evaluateDesiredMode()
        }

        // MARK: - Private: Mode Evaluation

        /// 현재 상태(pointerInputMode, HW 마우스 연결, 전체 화면)에 따라 적절한 모드를 결정합니다.
        private func desiredMode() -> HIDIOSessionMode {
            switch pointerInputMode {
            case .touchPointer:
                return .shared

            case .hardwareMouse, .automatic:
                let isIPad = DeviceKind.current == .iPad
                if isHardwareMouseConnected && isFullScreen && isIPad {
                    return .limitedExclusive
                } else {
                    return .shared
                }
            }
        }

        /// 현재 상태에 기반하여 모드 전환이 필요한지 평가하고, 필요 시 자동 전환합니다.
        @MainActor
        private func evaluateDesiredMode() {
            let desired = desiredMode()
            guard desired != mode else { return }

            let reason: HIDIOSessionModeSwitchReason
            if desired == .shared && (pointerInputMode == .hardwareMouse || pointerInputMode == .automatic) {
                // 조건(iPad + 전체 화면 + HW 마우스) 미충족으로 인한 폴백
                reason = .unsupportedMode
            } else {
                reason = .userInitiated
            }

            logger.info("Auto-switching mode: \(self.mode) -> \(desired) (reason: \(reason))")
            try? session.switchMode(to: desired, reason: reason)
        }
         */
    }
}
#endif
