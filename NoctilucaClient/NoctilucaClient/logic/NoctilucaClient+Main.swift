//
//  NoctilucaClient+Auth.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/11/25.
//

import Foundation
import Combine

import SiriusKitClient

extension NoctilucaClient {
    func initializeHIDIO() async throws {
        guard let channel = try await session.channelManager.openChannel(for: .hidio, identifier: ChannelIdentifier()) as? HIDIOChannel else {
            // FIXME
            return
        }
        
        self.hidioController = HIDIOController(channel: channel)
        self.hidioController?.onEventTapError = { [weak self] error in
            self?.handleEventTapError(error)
        }
        self.logger.info("initializeHIDIO(): created HIDIOController")
        applyInputFocusState()
        applyInputRedirectionMethod(pendingInputRedirectionMethod)
    }

    func applyInputRedirectionMethod(_ method: AppSettings.InputRedirectionMethod) {
        pendingInputRedirectionMethod = method

        guard hidioController != nil else {
            return
        }
        
        connectGameControllerMouse()

        switch method {
        case .gameController:
#if os(macOS)
            HIDIOInputRouter.shared.disconnect(.cocoaEventTapKeyboard)
#endif
            connectGameControllerKeyboard()
            updateInputWarning(nil)
        case .cocoaEventTap:
#if os(macOS)
            guard TCCUtil.shared.isAccessGranted(for: .inputMonitoring) else {
                updateInputWarning(InputWarning(
                    kind: .inputMonitoringRequired,
                    title: "Input Monitoring 권한 필요",
                    message: "Cocoa Event Tap을 사용하려면 입력 모니터링 권한이 필요합니다. 현재 GameController로 입력을 전송 중입니다."
                ))
                HIDIOInputRouter.shared.disconnect(.cocoaEventTapKeyboard)
                connectGameControllerKeyboard()
                return
            }

            HIDIOInputRouter.shared.disconnect(.gcKeyboard)
            let eventTapDevice = HIDIOCocoaEventTapKeyboard.shared()
            HIDIOInputRouter.shared.connectGlobal(eventTapDevice)
            updateInputWarning(nil)
#else
            connectGameControllerKeyboard()
            updateInputWarning(nil)
#endif
        }
    }

    private func connectGameControllerKeyboard() {
        guard let keyboard = HIDIOGCKeyboard.shared() else {
            self.logger.warning("HIDIO: GCKeyboard is not available")
            return
        }

        self.logger.info("HIDIO: connected GCKeyboard")
        HIDIOInputRouter.shared.connectGlobal(keyboard)
    }
    
    private func connectGameControllerMouse() {
        guard let mouse = HIDIOGCMouse.shared() else {
            self.logger.warning("HIDIO: GCMouse is not available")
            return
        }

        self.logger.info("HIDIO: connected GCMouse")
        HIDIOInputRouter.shared.connectGlobal(mouse)
    }

    private func handleEventTapError(_ error: Error) {
        updateInputWarning(InputWarning(
            kind: .eventTapUnavailable,
            title: "Cocoa Event Tap 초기화 실패",
            message: "Cocoa Event Tap 초기화에 실패했습니다. 현재 GameController로 입력을 전송 중입니다."
        ))

#if os(macOS)
        HIDIOInputRouter.shared.disconnect(.cocoaEventTapKeyboard)
#endif
        connectGameControllerKeyboard()
    }

    private func updateInputWarning(_ warning: InputWarning?) {
        Task {
            await MainActor.run {
                self.uiEvents.send(.inputWarningUpdated(warning))
            }
        }
    }

#if os(macOS)
    func setInputCaptureModeEnabled(_ enabled: Bool) {
        /*
        guard let device = hidioController?.device(for: .keyboard) as? HIDIOCocoaEventTapKeyboard else {
            return
        }

        device.setCaptureModeEnabled(enabled)
         */
    }

    func toggleInputCaptureMode() {
        /*
        guard let device = hidioController?.device(for: .keyboard) as? HIDIOCocoaEventTapKeyboard else {
            return
        }

        device.toggleCaptureMode()
         */
    }
#endif
    
    func initializeProjection() async throws {
        guard let channel = try await session.channelManager.openChannel(for: .projection, identifier: ChannelIdentifier()) as? ProjectionChannel else {
            // FIXME
            return
        }
        
        self.projectionChannel = channel
        self.logger.info("initializeProjection(): created ProjectionChannel")
        
        let session = try await channel.createSession(projectionSettings: sessionSettings?.projection)
        self.logger.info("initializeProjection(): created sample session")
        
        await MainActor.run {
            self.uiEvents.send(.FIXME_projectionStarted(session))
        }
    }
    
    
    func startSession() async throws {
        try assertPhase(expected: .ready)
        
        try await initializeHIDIO()
        try await initializeProjection()
    }
}
