//
//  Untitled.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/6/26.
//

#if os(macOS)
import Foundation
import AppKit

import SiriusKitClient

extension HIDIOSession {
    class MacOSDriver: Driver {
        private let logger = NoctilucaLogger(category: "HIDIOSession.MacOSDriver")
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
        
        var currentKeyboard: HIDIOVirtualDevice?
        var currentMouse: HIDIOVirtualDevice?

        required init(_ session: HIDIOSession) {
            self._session = session
        }
        
        @MainActor
        func startSession() throws -> HIDIOSessionMode {
            // 기본은 shared mode.
            try switchMode(to: .shared, reason: .userInitiated)

            // key window가 아니면 세션의 키보드 disconnect (나중에 activateSession()에서 재연결)
            if _session?.window?.isKeyWindow != true {
                if let keyboard = currentKeyboard {
                    controller.disconnect(keyboard.identifierString)
                }
            }

            defer {
                delegate?.hidioSession(session, didChangeState: .active)
            }

            return .shared
        }
        
        @MainActor
        func stopSession() {
            defer {
                delegate?.hidioSession(session, didChangeState: .inactive)
            }

            if let keyboard = currentKeyboard {
                controller.disconnect(keyboard.identifierString)
            }
            if let mouse = currentMouse {
                controller.disconnect(mouse.identifierString)
            }
            controller.resetKeyPressState()

            self.currentKeyboard = nil
            self.currentMouse = nil
        }

        func activateSession() {
            // 원격 세션 창이 다시 활성화 되었습니다, 키보드를 다시 연결합니다.
            if let keyboard = currentKeyboard {
                controller.connect(keyboard)
            }
            
            if mode == .exclusive {
                // exclusive 모드인 경우 마우스도 다시 연결합니다.
                if let mouse = currentMouse {
                    controller.connect(mouse)
                }
            }
        }
        
        func deactivateSession() {
            // 원격 세션 창이 비활성화 되었습니다, 키보드를 해제합니다.
            if let keyboard = currentKeyboard {
                controller.disconnect(keyboard.identifierString)
            }

            if mode != .shared {
                // exclusive 모드인 경우 마우스도 해제합니다.
                if let mouse = currentMouse {
                    controller.disconnect(mouse.identifierString)
                }
            }

            controller.resetKeyPressState()
        }
        
        @MainActor
        func switchMode(to mode: HIDIOSessionMode, reason: HIDIOSessionModeSwitchReason) throws {
            if let keyboard = currentKeyboard {
                controller.disconnect(keyboard.identifierString)
            }
            if let mouse = currentMouse {
                controller.disconnect(mouse.identifierString)
            }
            controller.resetKeyPressState()

            self.currentKeyboard = nil
            self.currentMouse = nil

            if (mode == .shared) {
                // 1. shared mode에서는 GCKeyboard를 연결한다
                let keyboard = HIDIOGCKeyboard.shared()
                self.currentKeyboard = keyboard
                controller.connect(keyboard)
                
                // 2. shared mode에서는 AppKit / NSEvent 기반 마우스를 연결한다
                let mouse = HIDIOAppKitPointer()
                self.currentMouse = mouse
                controller.connect(mouse)
            } else if (mode == .exclusive) {
                // 1. exclusive mode에서는 CocoaEventTapKeyboard를 연결한다
                do {
                    // TODO: 얘 ctor에 a11y tcc 체크하고, 없으면 터져야 함
                    // FIXME: 아니 왜 토글 숏컷이나 그런게 얘 ctor에 있어요;;;
                    let keyboard = try HIDIOCocoaEventTapKeyboard.acquire()
                    self.currentKeyboard = keyboard
                    controller.connect(keyboard)
                    
                    // 2. exclusive mode에서는 relative 마우스를 연결한다
                    if let mouse = HIDIOGCMouse.shared() {
                        mouse.window = session.window
                        self.currentMouse = mouse
                        controller.connect(mouse)
                    } else {
                        logger.warning("Failed to acquire shared GCMouse instance; is there any mouse device connected?")
                    }
                } catch {
                    logger.error("Failed to create CocoaEventTapKeyboard: \(error); falling back to shared mode")
                    try? switchMode(to: .shared, reason: .unsupportedMode)
                    
                    // 롤백한 뒤 오류 던짐
                    throw error
                }
            }
            
            delegate?.hidioSession(session, didSwitchMode: mode, reason: reason)
        }
        
        @MainActor
        func switchableModes() -> Set<HIDIOSessionMode> {
            var switchableModes: Set<HIDIOSessionMode> = []
            let currentMode = session.mode
            
            if currentMode != .shared {
                switchableModes.insert(.shared)
            }
            
            if TCCUtil.shared.isAccessGranted(for: .accessibility),
               currentMode != .exclusive {
                switchableModes.insert(.exclusive)
            }
            
            return switchableModes
        }
    }
}
#endif
