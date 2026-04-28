//
//  HIDIO.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/6/26.
//

import Foundation
import Combine
import Observation

#if os(macOS)
import AppKit
#endif

import SiriusKitCore

extension RemoteSession {
    @MainActor
    @Observable
    final class HIDIO {
        @ObservationIgnored
        private unowned let parent: RemoteSession

        let channelID: UUID
        @ObservationIgnored
        let controller: HIDIOController

        @ObservationIgnored
        private let rebinder = KeyEventRebinder()
        @ObservationIgnored
        private var cancellables: Set<AnyCancellable> = []

        @ObservationIgnored
        private(set) var session: HIDIOSession!

        private(set) var sessionState: HIDIOSessionState = .inactive

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
#if os(macOS)
                self.installModeToggleHook()
#endif
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

#if os(macOS)
        private static let modeToggleHookIdentifier = HIDIOKeystrokeHookIdentifier(
            rawValue: "app.noctiluca.navigator.hidio.mode-toggle-hook"
        )

        /// 독점 ↔ 공유 모드를 토글하는 단축키 훅. macOS 에서만 의미가 있다.
        /// (iOS / iPadOS 에서는 `HIDIOSessionMode.exclusive` 를 사용할 수 없다.)
        private func installModeToggleHook() {
            let toggleSequence = SettingsStore.shared.settings.input.toggleExclusiveModeKeySequence
            let hook = HIDIOKeystrokeHook(
                condition: toggleSequence,
                swallowsTriggerKey: true
            ) { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    let target: HIDIOSessionMode =
                        (self.session.mode == .exclusive) ? .shared : .exclusive
                    try? self.session.switchMode(to: target, reason: .userInitiated)
                }
            }

            controller.installHook(hook, for: Self.modeToggleHookIdentifier)
        }
#endif

        @MainActor
        deinit {
            let controller = self.controller
            let session: HIDIOSession? = self.session
#if os(macOS)
            controller.removeHook(for: Self.modeToggleHookIdentifier)
#endif
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
