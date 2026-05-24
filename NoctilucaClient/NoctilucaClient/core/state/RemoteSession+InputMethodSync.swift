//
//  RemoteSession+InputMethodSync.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 5/23/26.
//

#if os(macOS)

import Foundation
import Combine
import Observation

import Carbon
import Carbon.HIToolbox

import SiriusKitClient

extension RemoteSession {
    /// 클라이언트(navigator) 의 macOS 입력 소스(IM) 변경을 감지하여, simplerpc 채널로
    /// 호스트에 동일 언어 IM 으로의 전환을 요청한다. (단방향 — 호스트 → 클라이언트
    /// 역방향은 지원하지 않는다.)
    ///
    /// 호스트 측의 RPC 핸들러는 `app.noctiluca.rpc.switch-im` 오퍼레이션으로 매칭되며,
    /// 첫 번째 인자로 BCP-47 언어 태그, 두 번째 인자로 서드/퍼스트 파티 우선 지정을 받는다.
    /// (`CJKSwitchInputMethodRPCHandler` 참고.)
    ///
    /// 라이프사이클은 `RemoteSession` 의 `simpleRPC` 채널이 열리는 동안 유효하며,
    /// `RemoteSession.handleChannelOpen(channel:for:)` 에서 생성하고
    /// `handleChannelClose` 에서 해제한다.
    @MainActor
    @Observable
    final class InputMethodSync {
        @ObservationIgnored
        private let logger = NoctilucaLogger(category: "InputMethodSync")

        @ObservationIgnored
        private unowned let parent: RemoteSession

        let channelID: UUID

        @ObservationIgnored
        private let channel: SimpleRPCChannel

        @ObservationIgnored
        private var cancellables: Set<AnyCancellable> = []

        @ObservationIgnored
        private var observerInstalled: Bool = false

        @ObservationIgnored
        private var debounceTask: Task<Void, Never>?

        @ObservationIgnored
        private var inFlightTask: Task<Void, Never>?

        /// 직전에 송신한 (BCP-47, preferThirdParty) 조합. 동일 값이 연속으로 들어오면 skip 한다.
        @ObservationIgnored
        private var lastSent: (languageTag: String, preferThirdParty: Bool)?

        /// 변경 알림 콜백에서 메인 액터로 hop 하기 위한 핸들.
        @ObservationIgnored
        private var observerSelfPtr: UnsafeMutableRawPointer?

        /// `invalidate()` 가 호출된 적이 있는지. 한번 invalidate 된 인스턴스는 더 이상 자원을
        /// 재취득하지 않는다 (observer 재설치 / task 재스케줄 금지). deinit 이 늦게 와도
        /// 안전하게 동작하기 위한 가드.
        @ObservationIgnored
        private var isInvalidated: Bool = false

        private static let debounceInterval: Duration = .milliseconds(100)

        init(_ parent: RemoteSession, channel: SimpleRPCChannel) {
            self.parent = parent
            self.channelID = channel.identifier
            self.channel = channel

            subscribeSettings()
        }

        @MainActor
        deinit {
            // 정상 흐름에서는 `RemoteSession.handleChannelClose` 가 이미 invalidate() 를
            // 호출했지만, safety net 으로 한번 더 호출한다. idempotent.
            performInvalidate()
        }

        // MARK: - Invalidation

        /// 모든 외부 자원(observer, in-flight task, Combine 구독)을 즉시 해제한다.
        ///
        /// in-flight task 의 strong-self 캡처(혹은 그 외 retain) 때문에 deinit 이 지연되거나
        /// 호출되지 않더라도 distributed notification observer 가 계속 fire 하는 leak 을
        /// 방지하기 위한 명시적 teardown 진입점. `RemoteSession.handleChannelClose` 에서
        /// nil 할당 전에 반드시 호출해야 한다.
        ///
        /// 멱등(idempotent). 두번 이상 호출돼도 안전하다.
        func invalidate() {
            performInvalidate()
        }

        private func performInvalidate() {
            guard !isInvalidated else { return }
            isInvalidated = true

            debounceTask?.cancel()
            debounceTask = nil
            inFlightTask?.cancel()
            inFlightTask = nil
            cancellables.removeAll()
            removeObserverIfInstalled()
            lastSent = nil
        }

        // MARK: - Settings binding

        private func subscribeSettings() {
            let initial = SettingsStore.shared.settings?.input.syncIMState ?? false
            applySyncEnabled(initial)

            SettingsStore.shared.$settings
                .compactMap { $0?.input.syncIMState }
                .removeDuplicates()
                .dropFirst()
                .sink { [weak self] enabled in
                    guard let self else { return }
                    self.applySyncEnabled(enabled)
                }
                .store(in: &cancellables)
        }

        private func applySyncEnabled(_ enabled: Bool) {
            guard !isInvalidated else { return }
            if enabled {
                installObserverIfNeeded()
                scheduleSend(reason: "initial / enabled")
            } else {
                removeObserverIfInstalled()
                debounceTask?.cancel()
                inFlightTask?.cancel()
                lastSent = nil
            }
        }

        // MARK: - Distributed notification observer

        private func installObserverIfNeeded() {
            guard !observerInstalled else { return }

            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            self.observerSelfPtr = selfPtr

            CFNotificationCenterAddObserver(
                CFNotificationCenterGetDistributedCenter(),
                selfPtr,
                { _, observer, _, _, _ in
                    guard let observer else { return }
                    // 콜백 스레드가 명시되지 않으므로 메인 액터로 hop.
                    Task { @MainActor in
                        let sync = Unmanaged<InputMethodSync>
                            .fromOpaque(observer)
                            .takeUnretainedValue()
                        sync.handleInputSourceChanged()
                    }
                },
                kTISNotifySelectedKeyboardInputSourceChanged,
                nil,
                .deliverImmediately
            )

            observerInstalled = true
        }

        private func removeObserverIfInstalled() {
            guard observerInstalled, let selfPtr = observerSelfPtr else { return }
            CFNotificationCenterRemoveEveryObserver(
                CFNotificationCenterGetDistributedCenter(),
                selfPtr
            )
            observerInstalled = false
            observerSelfPtr = nil
        }

        private func handleInputSourceChanged() {
            scheduleSend(reason: "kTISNotifySelectedKeyboardInputSourceChanged")
        }

        // MARK: - Debounce + send

        private func scheduleSend(reason: String) {
            guard !isInvalidated else { return }
            debounceTask?.cancel()
            debounceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.debounceInterval)
                guard !Task.isCancelled else { return }
                self?.fireSend(reason: reason)
            }
        }

        private func fireSend(reason: String) {
            guard !isInvalidated else { return }
            guard let languageTag = currentInputSourceLanguageTag() else {
                logger.warning("Failed to extract BCP-47 from current input source — skipping (\(reason))")
                return
            }

            let preferThirdParty =
                SettingsStore.shared.settings?.input.syncIMStatePreferThirdParty ?? false

            if let lastSent,
               lastSent.languageTag == languageTag,
               lastSent.preferThirdParty == preferThirdParty {
                return
            }

            inFlightTask?.cancel()
            // `guard let self` 로 strong promote 하지 않는다 — sendRequest 가 channel close
            // 와의 race 등으로 즉시 throw 되지 않으면 self 가 task 에 잡혀서 deinit 이 영영
            // 호출되지 않고, observer 가 계속 fire 하는 leak 으로 이어진다.
            // 대신 channel 만 task 로 옮겨 잡고, self 는 weak 로 유지한다.
            inFlightTask = Task { @MainActor [weak self, channel] in
                let args = [
                    languageTag,
                    preferThirdParty ? "prefer-third-party" : "prefer-first-party"
                ]

                do {
                    _ = try await channel.sendRequest(
                        operation: "app.noctiluca.rpc.switch-im",
                        args: args
                    )
                    guard let self, !Task.isCancelled else { return }
                    self.lastSent = (languageTag, preferThirdParty)
                    self.logger.info("Synced IM to host: \(languageTag) (preferThirdParty=\(preferThirdParty), reason=\(reason))")
                } catch is CancellationError {
                    // 다음 변경 / debounce 에 의해 취소된 경우는 정상 흐름.
                } catch {
                    self?.logger.warning("Failed to sync IM to host: \(error) (reason=\(reason))")
                }
            }
        }

        // MARK: - TIS query

        /// 현재 선택된 입력 소스의 `kTISPropertyInputSourceLanguages` 첫 번째 BCP-47 태그.
        /// 빈 배열이거나 추출 실패 시 nil.
        private func currentInputSourceLanguageTag() -> String? {
            guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
                return nil
            }
            guard let pointer = TISGetInputSourceProperty(
                source,
                kTISPropertyInputSourceLanguages
            ) else {
                return nil
            }
            let languages = Unmanaged<CFArray>
                .fromOpaque(pointer)
                .takeUnretainedValue() as? [String]
            guard let first = languages?.first, !first.isEmpty else {
                return nil
            }
            return first
        }
    }
}

#endif
