//
//  RemoteSession.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/28/26.
//
import Foundation
import Combine
import Security

import SiriusKitClient

@MainActor
class RemoteSession: ObservableObject {
    private let logger = NoctilucaLogger(category: "RemoteSession")
    private var eventSubscription: AnyCancellable? = nil
    
    var parent: Weak<SessionWindowViewModel>?

    private(set) var client: NoctilucaClient

    @Published
    private(set) var phase: NoctilucaClientPhase = .initial

    @Published
    private(set) var authChallenge: AuthChallenge? = nil

    @Published
    var shouldPresentAuthChallengeSheet: Bool = false

    @Published
    var shouldPresentIdentityValidationSheet: Bool = false

    @Published
    private(set) var pendingServerIdentity: ServerIdentity? = nil

    @Published
    private(set) var identityValidationExtraInfo: ServerIdentityValidationSheetViewExtraInfo = .none

    @Published
    private(set) var pingRTT: TimeInterval? = nil
    
    @Published
    private(set) var projection: Projection? = nil
    
    @Published
    private(set) var hidio: HIDIO? = nil
    
    private let errorEvents = PassthroughSubject<NoctilucaClientError, Never>()

    var errorPublisher: AnyPublisher<NoctilucaClientError, Never> {
        errorEvents.eraseToAnyPublisher()
    }

    var availableAuthMethods: [ClientAuthMethod] {
        guard let authChallenge else {
            return []
        }
        
        return client.authenticator.availableMethods(for: authChallenge)
    }

    init(_ client: NoctilucaClient) {
        self.client = client
        
        self.subscribeClientEvents()
    }
    
    @MainActor
    deinit {
        self.unsubscribeClientEvents()

        let client = self.client
        guard client.phase != .closed else {
            return
        }

        logger.warning("RemoteSession.deinit: client is not closed (phase=\(client.phase)). Triggering safety-net cleanup. This indicates a missing explicit cleanup call.")
        Task.detached {
            await client.close()
        }
    }
    
    func setup() async throws {
        try await self.client.setup()
    }
    
    func startup() async throws {
        try await self.client.startup()
    }
    
    func shutdown() async {
        await self.client.close()
    }

    private func subscribeClientEvents() {
        self.eventSubscription = client.uiEvents
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    self?.handleEvent(event)
                }
            }

        // manually update current phase
        self.phase = client.phase
    }

    private func unsubscribeClientEvents() {
        self.eventSubscription?.cancel()
        self.eventSubscription = nil
    }

    /// ViewModel에서 세션을 분리할 때 호출. 이벤트 구독과 parent 참조를 정리한다.
    func prepareForDetach() {
        unsubscribeClientEvents()
        parent = nil
    }

    private func handleEvent(_ event: NoctilucaClientUIEvent) {
        switch event {
        case .phaseChanged(let phase):
            self.phase = phase
            // self.mainWindowViewModel.handleClientPhaseChanged(phase)

        case .receivedAuthChallenge(let authChallenge):
            self.authChallenge = authChallenge
            self.shouldPresentAuthChallengeSheet = true

        case .receivedAuthResponse(let authResponse):
            self.logger.info("Received auth response: \(authResponse.sessionID?.uuidString ?? "(nil)")")
            self.authChallenge = nil
            self.shouldPresentAuthChallengeSheet = false

        case .pingRTTUpdated(let rtt):
            self.pingRTT = rtt
            break
            
        /*
        case .inputWarningUpdated(let warning):
            self.mainWindowViewModel.handleInputWarningUpdated(warning)
         */

        case .errorOccurred(let error):
            self.logger.error("Client error occurred: \(error.localizedDescription)")
            // 재전송
            self.errorEvents.send(error)

        case .channelCreated(let feature, let channel):
            self.handleChannelOpen(channel: channel, for: feature)
        case .channelClosed(let channelID):
            self.handleChannelClose(channelID)

        case .serverIdentityValidationNeeded(let identity):
            Task {
                do {
                    try await self.handleIdentityValidationRequest(identity: identity)
                } catch {
                    logger.error("Failed to handle identity validation request: \(error.localizedDescription)")
                    self.errorEvents.send(.connectionFailed(error))
                    await self.parent?._ref?.stopSession(force: true)
                }
            }
        }
    }

    func handleIdentityValidationRequest(identity: ServerIdentity) async throws {
        guard let parent = self.parent?.ref else {
            return
        }
        
        let endpointURL = parent.endpointURL
        var extraInfo: ServerIdentityValidationSheetViewExtraInfo = .none
        
        if let knownHost = try await KeychainBackedKnownHostStore.shared.getKnownHost(endpoint: endpointURL) {
            let fingerprint = try identity.fingerprint()

            if knownHost.fingerprint == fingerprint {
                // 이미 신뢰된 호스트임
                logger.info("Server identity matches known host. Automatically trusting.")
                do {
                    try await parent.performReconnect(decision: SucceedValidationDecision(fingerprint: fingerprint, decision: .allow))
                    return
                } catch {
                    // auto-trust 재접속 실패 시 에러 표시 (performReconnect가 이미 세션을 정리했으므로 시트 폴백 불가)
                    logger.warning("Auto-trust reconnect failed: \(error.localizedDescription)")
                    parent.presentConnectionError(error)
                    return
                }
            } else {
                // 지문 불일치 일어남, 사용자에게 경고해야 함.
                extraInfo = .fingerprintMismatch(
                    expectedFingerprint: knownHost.fingerprint.asFingerprintString(),
                    actualFingerprint: fingerprint.asFingerprintString()
                )
                
                // UI 프레젠테이션으로 넘어간다
            }
        }
        
        self.pendingServerIdentity = identity
        self.identityValidationExtraInfo = extraInfo
        self.shouldPresentIdentityValidationSheet = true
    }

    func handleAuthChallengeResponse(_ action: AuthChallengeSheetAction) async {
        guard let authChallenge else {
            return
        }

        self.shouldPresentAuthChallengeSheet = false

        switch action {
        case .cancel:
            await client.close()
            return
        case .confirm(let entry):
            guard var payload = client.authenticator.payload(for: entry, nonce: authChallenge.nonce) else {
                client.logger.error("Failed to build auth payload for method: \(entry.method.rawValue)")
                return
            }
            defer { payload.zeroize() }
            try? await client.sendAuthRequest(entry.method.rawValue, nonce: authChallenge.nonce, payload: payload)
        }
    }
    
    private func handleChannelOpen(channel: Channel, for feature: SiriusFeature) {
        switch feature {
        case .projection:
            guard let projectionChannel = channel as? ProjectionChannel else {
                return
            }

            self.projection = Projection(self, channel: projectionChannel)
            Task { [weak self] in
                guard let self else {
                    return
                }

                do {
                    try await self.projection?.startAudioProjection()
                } catch {
                    self.handleAudioProjectionInitializationFailure(error)
                }
            }
            
        case .hidio:
            guard let hidioChannel = channel as? HIDIOChannel else {
                return
            }
            
            self.hidio = HIDIO(self, channel: hidioChannel)
        default:
            break
        }
    }
    
    private func handleChannelClose(_ channelID: UUID) {
        if channelID == projection?.channelID {
            self.projection = nil
        }
        
        if channelID == hidio?.channelID {
            self.hidio = nil
        }
    }

    private func handleAudioProjectionInitializationFailure(_ error: Error) {
        let message = makeAudioProjectionErrorMessage(from: error)
        self.logger.error("Audio projection initialization failed: \(message)")
        self.errorEvents.send(.audioProjectionInitializationFailed(message: message))
    }

    private func makeAudioProjectionErrorMessage(from error: Error) -> String {
        guard let projectionError = error as? ProjectionChannelError else {
            return error.localizedDescription
        }

        switch projectionError {
        case .audioSessionCreationFailed(_, let reason, let message):
            let reasonDescription: String
            switch reason {
            case .codecNotSupported:
                reasonDescription = String(localized: "error.audio.codec_not_supported", defaultValue: "서버와 공통으로 사용할 수 있는 오디오 코덱이 없습니다.")
            case .permissionDenied:
                reasonDescription = String(localized: "error.audio.permission_denied", defaultValue: "서버가 오디오 캡처 권한을 거부했습니다.")
            case .sourceNotFound:
                reasonDescription = String(localized: "error.audio.source_not_found", defaultValue: "요청한 오디오 소스를 찾을 수 없습니다.")
            default:
                reasonDescription = String(localized: "error.audio.session_creation_rejected", defaultValue: "서버가 오디오 세션 생성을 거부했습니다.")
            }

            if let message, !message.isEmpty {
                return "\(reasonDescription)\n\(message)"
            }
            return reasonDescription

        case .audioSessionCreationTimedOut(_, let timeout):
            return String(format: String(localized: "error.audio.session_creation_timed_out", defaultValue: "오디오 세션 생성 응답이 %d초 안에 도착하지 않았습니다."), Int(timeout))
        case .audioSessionStartFailed(_, let underlying):
            return String(format: String(localized: "error.audio.session_start_failed", defaultValue: "오디오 세션 시작 중 오류가 발생했습니다.\n%@"), underlying.localizedDescription)
        case .channelClosed:
            return String(localized: "error.audio.channel_closed", defaultValue: "프로젝션 채널이 닫혀 오디오를 시작할 수 없습니다.")
        case .sessionCreationCancelled:
            return String(localized: "error.audio.session_creation_cancelled", defaultValue: "오디오 세션 생성이 취소되었습니다.")
        }
    }
}
