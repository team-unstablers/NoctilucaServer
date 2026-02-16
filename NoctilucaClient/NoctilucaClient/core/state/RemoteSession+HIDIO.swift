//
//  HIDIO.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/6/26.
//

import Foundation
import Combine

#if os(macOS)
import AppKit
#endif

import SiriusKitCore

extension RemoteSession {
    class HIDIO: ObservableObject {
        private let parent: Weak<RemoteSession>
        private let channel: Weak<HIDIOChannel>

        private let rebinder = KeyEventRebinder()
        private var cancellables: Set<AnyCancellable> = []

        private(set) var session: HIDIOSession!

        @Published
        private(set) var sessionState: HIDIOSessionState = .inactive

        @Published
        private(set) var sessionMode: HIDIOSessionMode = .shared

        var channelID: UUID {
            channel.ref.identifier
        }

        var controller: HIDIOController {
            channel.ref.controller
        }

        init(_ parent: RemoteSession, channel: HIDIOChannel) {
            self.parent  = Weak(parent)
            self.channel = Weak(channel)

            self.session = HIDIOSession(controller)
            session.delegate = self
            
            Task { @MainActor in
#if os(iOS)
                session.rootViewController = self.parent.ref.parent?.ref.rootViewController
#endif
#if os(macOS)
                session.window = self.parent.ref.parent?.ref.mainWindowController?.ref.window
#endif

                self.setupKeyEventPipeline()
                self.sendKeyboardSetupIfNeeded()
                try? self.session.startSession()
                self.installEscapeHook()
            }
        }

        private func setupKeyEventPipeline() {
            controller.keyEventPipeline.append(rebinder)

            let overrides = SettingsStore.shared.settings.input.modifierKeyOverrides
            ModifierKeyRebindingConfigurator.apply(overrides, to: rebinder)

            SettingsStore.shared.$settings
                .compactMap { $0?.input.modifierKeyOverrides }
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] overrides in
                    guard let self else { return }
                    ModifierKeyRebindingConfigurator.apply(overrides, to: self.rebinder)
                }
                .store(in: &cancellables)
        }

    
        @MainActor
        private func sendKeyboardSetupIfNeeded() {
            let sessionSettings = parent.ref.client.sessionSettings
            let appSettings = SettingsStore.shared.settings!
            let enabledHacks = sessionSettings?.input.enabledKeyboardHacks
                ?? appSettings.sessionDefaults.input.enabledKeyboardHacks

            guard !enabledHacks.isEmpty else { return }

            let hacks = enabledHacks.map { KeyboardHack(identifier: $0, args: [:]) }
            controller.sendKeyboardSetup(hacks: hacks)
        }

        private func installEscapeHook() {
            let escapeSequence = SettingsStore.shared.settings.input.unlockKeySequence
            let hook = HIDIOKeystrokeHook(condition: escapeSequence) {
                Task { @MainActor in
                    try? self.session.switchMode(to: .shared, reason: .userInitiated)
                }
            }

            controller.installHook(hook, for: .init(rawValue: "app.noctiluca.navigator.hidio.escape-hook"))
        }

        deinit {
            self.session.stopSession()
        }
    }
}

extension RemoteSession.HIDIO: HIDIOSessionDelegate {
    func hidioSession(_ session: HIDIOSession, didChangeState state: HIDIOSessionState) {
        Task { @MainActor in
            self.sessionState = state
        }
    }
    
    func hidioSession(_ session: HIDIOSession, didSwitchMode mode: HIDIOSessionMode, reason: HIDIOSessionModeSwitchReason) {
        Task { @MainActor in
            self.sessionMode = mode
        }
    }
}
