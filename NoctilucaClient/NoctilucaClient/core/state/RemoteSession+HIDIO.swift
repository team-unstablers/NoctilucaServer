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
    @MainActor
    final class HIDIO: ObservableObject {
        private unowned let parent: RemoteSession

        let channelID: UUID
        let controller: HIDIOController

        private let rebinder = KeyEventRebinder()
        private var cancellables: Set<AnyCancellable> = []

        private(set) var session: HIDIOSession!

        @Published
        private(set) var sessionState: HIDIOSessionState = .inactive

        @Published
        private(set) var sessionMode: HIDIOSessionMode = .shared

        init(_ parent: RemoteSession, channel: HIDIOChannel) {
            self.parent = parent
            self.channelID = channel.identifier
            self.controller = channel.controller

            self.session = HIDIOSession(controller)
            session.delegate = self
            
            Task { @MainActor in
#if os(iOS)
                session.rootViewController = self.parent.parent?.rootViewController
#endif
#if os(macOS)
                session.window = self.parent.parent?.mainWindowController?.window
#endif

                self.setupKeyEventPipeline()
                self.applyMouseInputSettings()
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

            SettingsStore.shared.$settings
                .compactMap { settings -> AppSettings.Input? in settings?.input }
                .dropFirst()
                .sink { [weak self] (input: AppSettings.Input) in
                    guard let self else { return }
                    self.controller.applyMouseInputSettings(input)
                }
                .store(in: &cancellables)
        }

    
        @MainActor
        private func sendKeyboardSetupIfNeeded() {
            let sessionSettings = parent.client.sessionSettings
            let appSettings = SettingsStore.shared.settings!
            let enabledHacks = sessionSettings?.input.enabledKeyboardHacks
                ?? appSettings.sessionDefaults.input.enabledKeyboardHacks

            guard !enabledHacks.isEmpty else { return }

            let hacks = enabledHacks.map { KeyboardHack(identifier: $0, args: [:]) }
            controller.sendKeyboardSetup(hacks: hacks)
        }

        private func applyMouseInputSettings() {
            let input = SettingsStore.shared.settings.input
            controller.applyMouseInputSettings(input)
        }

        private func installEscapeHook() {
            let escapeSequence = SettingsStore.shared.settings.input.unlockKeySequence
            let hook = HIDIOKeystrokeHook(condition: escapeSequence) { [weak self] in
                Task { @MainActor in
                    try? self?.session.switchMode(to: .shared, reason: .userInitiated)
                }
            }

            controller.installHook(hook, for: .init(rawValue: "app.noctiluca.navigator.hidio.escape-hook"))
        }

        @MainActor
        deinit {
            let controller = self.controller
            let session: HIDIOSession? = self.session
            controller.removeHook(
                for: HIDIOKeystrokeHookIdentifier(rawValue: "app.noctiluca.navigator.hidio.escape-hook")
            )
            session?.stopSession()
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
