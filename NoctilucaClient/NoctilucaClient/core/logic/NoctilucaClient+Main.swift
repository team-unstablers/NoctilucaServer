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
        
        let controller = HIDIOController(channel: channel)
        self.hidioController = controller
        self.logger.info("initializeHIDIO(): created HIDIOController")

        let pointerRouter = PointerInputRouter(controller: controller)
        controller.pointerInputRouter = pointerRouter
        pointerRouter.updateInputMode(pendingPointerInputMode)
        
        // Enable capture lock to ensure mouse cursor is hidden/locked when connected
        controller.enableCaptureLock()

        connectGameControllerMouse(controller)
        applyInputRedirectionMethod(pendingInputRedirectionMethod)
    }

    func applyInputRedirectionMethod(_ method: AppSettings.InputRedirectionMethod) {
        pendingInputRedirectionMethod = method

        guard let hidioController else {
            return
        }

        switch method {
        case .gameController:
            connectGameControllerKeyboard(hidioController)
        case .cocoaEventTap:
#if os(macOS)
            guard TCCUtil.shared.isAccessGranted(for: .inputMonitoring) else {
                updateInputWarning(InputWarning(
                    kind: .inputMonitoringRequired,
                    title: "Input Monitoring 권한 필요",
                    message: "Cocoa Event Tap을 사용하려면 입력 모니터링 권한이 필요합니다. 현재 GameController로 입력을 전송 중입니다."
                ))
                connectGameControllerKeyboard(hidioController)
                return
            }

            let eventTapDevice = HIDIOCocoaEventTapKeyboard(
                onError: { [weak self] error in
                    self?.handleEventTapError(error)
                }
            )
            hidioController.connect(eventTapDevice)
#else
            connectGameControllerKeyboard(hidioController)
#endif
        }
    }

    func applyPointerInputMode(_ mode: AppSettings.PointerInputMode) {
        pendingPointerInputMode = mode
        hidioController?.pointerInputRouter?.updateInputMode(mode)
    }

    private func connectGameControllerKeyboard(_ hidioController: HIDIOController) {
        guard let keyboard = HIDIOGCKeyboard.shared() else {
            self.logger.warning("HIDIO: GCKeyboard is not available")
            return
        }

        self.logger.info("HIDIO: connected GCKeyboard")
        hidioController.connect(keyboard)
    }
    
    private func connectGameControllerMouse(_ hidioController: HIDIOController) {
        guard let mouse = HIDIOGCMouse.shared() else {
            self.logger.warning("HIDIO: GCMouse is not available")
            return
        }

        self.logger.info("HIDIO: connected GCMouse")
        hidioController.connect(mouse)
    }

    private func handleEventTapError(_ error: Error) {
        /*
        updateInputWarning(InputWarning(
            kind: .eventTapUnavailable,
            title: "Cocoa Event Tap 초기화 실패",
            message: "Cocoa Event Tap 초기화에 실패했습니다. 현재 GameController로 입력을 전송 중입니다."
        ))
         */

        if let hidioController {
            connectGameControllerKeyboard(hidioController)
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
        
        try await projectionChannel.subscribeCursorEvents()
        try await projectionChannel.updateDisplayLayout()
        _ = try await projectionChannel.subscribeDisplayChanges(eventMask: [.becamePrimary, .connected, .disconnected, .modified])
        
        // TODO: 이거 디스플레이 없는 컴퓨터에서 터지면 어쩌죠..?
        let primaryDisplayID = await projectionChannel.displayLayoutManager.primaryDisplayID ?? -1
        
        _ = try await channel.createSession(for: primaryDisplayID, projectionSettings: sessionSettings?.projection)
        self.logger.info("initializeProjection(): created sample session")
    }
    
    
    func startSession() async throws {
        try assertPhase(expected: .ready)
        
        try await initializeHIDIO()
        try await initializeProjection()
    }
}
