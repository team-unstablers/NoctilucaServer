//
//  Untitled.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/6/26.
//

#if os(iOS)
import Foundation

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

        required init(_ session: HIDIOSession) {
            self._session = session
            
            self.defaultKeyboard = HIDIOGCKeyboard.shared()
            self.defaultSubMouse = HIDIOUIKitMouse()
        }
        
        @MainActor
        func startSession() throws -> HIDIOSessionMode {
            // 기본은 shared mode.
            try switchMode(to: .shared, reason: .userInitiated)
            
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
            
            controller.disconnectAll(kind: .keyboard)
            controller.disconnectAll(kind: .mouse)
            controller.disconnectAll(kind: .pointer)
            controller.resetKeyPressState()
        }
        
        func activateSession() {
            // 원격 세션 창이 다시 활성화 되었습니다, 키보드를 다시 연결합니다.
            controller.connect(defaultKeyboard)
            controller.connect(defaultSubMouse)

            if let mouse = currentMouse {
                controller.connect(mouse)
            }
        }
        
        func deactivateSession() {
            controller.disconnectAll(kind: .keyboard)
            
            if let mouse = currentMouse {
                controller.disconnect(type(of: mouse).identifier)
            }
            
            controller.resetKeyPressState()
        }
        
        @MainActor
        func switchMode(to mode: HIDIOSessionMode, reason: HIDIOSessionModeSwitchReason) throws {
            controller.connect(defaultKeyboard)
            controller.connect(defaultSubMouse)

            if (mode == .shared) {
                if let mouse = currentMouse {
                    controller.disconnect(type(of: mouse).identifier)
                }
                
                self.currentMouse = nil
            } else if (mode == .limitedExclusive) {
                let mouse = HIDIOGCMouse()
                controller.connect(mouse)

                self.currentMouse = mouse
            }
            
            delegate?.hidioSession(session, didSwitchMode: mode, reason: reason)
        }
        
        @MainActor
        func switchableModes() -> Set<HIDIOSessionMode> {
            return [.shared, .limitedExclusive]
        }
    }
}
#endif
