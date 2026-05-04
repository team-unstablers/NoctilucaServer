//
//  RemoteSession.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/28/26.
//
import Foundation
import Combine
import Observation
import Security

import SiriusKitClient

@MainActor
@Observable
final class RemoteSession {
    @ObservationIgnored
    private let logger = NoctilucaLogger(category: "RemoteSession")
    @ObservationIgnored
    private var eventSubscription: AnyCancellable? = nil

    // 프로세스 내에서 RemoteSession 인스턴스를 식별하기 위한 ID.
    // RemoteSessionManager/SubDisplayCoordinator 등 외부 자원이 세션을 참조하는 데 사용된다.
    let id: UUID = UUID()

    weak var parent: SessionWindowViewModel?

    private(set) var client: NoctilucaClient

    private(set) var phase: NoctilucaClientPhase = .initial

    private(set) var authChallenge: AuthChallenge? = nil

    var shouldPresentAuthChallengeSheet: Bool = false

    var shouldPresentIdentityValidationSheet: Bool = false

    private(set) var pendingServerIdentity: ServerIdentity? = nil

    private(set) var identityValidationExtraInfo: ServerIdentityValidationSheetViewExtraInfo = .none

    private(set) var pingRTT: TimeInterval? = nil

    /// 파일 전송 진행률. `FileTransferProgressTracker`가 `@Observable`이므로
    /// 아래 computed property를 읽는 뷰는 tracker의 `aggregatedProgress`까지 자동 tracking 된다.
    var fileTransferProgress: Double? {
        progressTracker.aggregatedProgress
    }

    private(set) var projection: Projection? = nil

    private(set) var hidio: HIDIO? = nil

    private let progressTracker = FileTransferProgressTracker()

    @ObservationIgnored
    private let errorEvents = PassthroughSubject<NoctilucaClientError, Never>()
    
#if os(macOS)
    weak var appStreamWindowManager: AppStreamWindowManager? = nil
#endif

    // MARK: - fsaccess state

    /// 활성 fsaccess control channel. 한 connection 당 1 개로 제한된다.
    @ObservationIgnored
    weak var fsAccessChannel: FSAccessChannel?

    /// 활성 mount session 들. sessionId → session.
    @ObservationIgnored
    var fsAccessMountSessions: [UUID: FSAccessMountSession] = [:]

    /// Stream R/W 의 outgoing/incoming TransferChannel 라우팅용. transferId → route.
    @ObservationIgnored
    var fsAccessStreamRoutes: [UUID: FSAccessStreamRoute] = [:]

    /// 현재 표시 중인 mount consent 요청. UI 바인딩용.
    var activeFSAccessConsentRequest: FSAccessConsentRequest? = nil

    @ObservationIgnored
    private var pendingFSAccessConsents: [(FSAccessConsentRequest, CheckedContinuation<FSAccessConsentDecision, Never>)] = []
    @ObservationIgnored
    private var activeFSAccessConsentContinuation: CheckedContinuation<FSAccessConsentDecision, Never>?

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

        // FeatureProvider 에 진행률 트래커 주입 (actor state 경유).
        if let featureProvider = client.noctilucaFeatureProvider {
            let tracker = progressTracker
            Task { await featureProvider.setProgressTracker(tracker) }
        }

        // fsaccess: 채널이 RemoteSession 의 lifecycle/consent 상태에 도달할 수 있도록 weak 참조 + broker 등록.
        client.fsAccessRemoteSession = self
        client.fsAccessConsentBroker = self

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
        progressTracker.reset()
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
                    await self.parent?.stopSession(force: true)
                }
            }
        }
    }

    func handleIdentityValidationRequest(identity: ServerIdentity) async throws {
        guard let parent = self.parent else {
            return
        }

        let endpointURL = parent.endpointURL
        var extraInfo: ServerIdentityValidationSheetViewExtraInfo = .none

        // 시스템 트러스트 스토어에서 명시적으로 거부된 인증서인지 확인
        if case .sslCertificate(let leaf, let chain) = identity,
           containsDeniedCertificate(in: [leaf] + chain) {
            self.pendingServerIdentity = identity
            self.identityValidationExtraInfo = .denied
            self.shouldPresentIdentityValidationSheet = true
            return
        }

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
            
            // FIXME
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

    // MARK: - fsaccess channel lifecycle

    /// 단일 인스턴스 강제. 이미 활성 channel 이 있으면 false 를 반환하여 caller 가 reject 하도록.
    func registerFSAccessChannel(_ channel: FSAccessChannel) -> Bool {
        if fsAccessChannel != nil {
            return false
        }
        fsAccessChannel = channel
        return true
    }

    func unregisterFSAccessChannel(_ channel: FSAccessChannel) {
        if fsAccessChannel === channel {
            fsAccessChannel = nil
        }
        // 부수적으로 mount session 들도 정리한다 (cascade close 의 끝).
        let snapshot = fsAccessMountSessions
        fsAccessMountSessions.removeAll()
        for session in snapshot.values {
            session.setMountChannel(nil)
        }
        // 진행 중인 stream route 도 정리.
        fsAccessStreamRoutes.removeAll()
        // 진행 중인 consent 도 deny 로 닫는다.
        if let cont = activeFSAccessConsentContinuation {
            activeFSAccessConsentContinuation = nil
            activeFSAccessConsentRequest = nil
            cont.resume(returning: .deny)
        }
        for (_, cont) in pendingFSAccessConsents {
            cont.resume(returning: .deny)
        }
        pendingFSAccessConsents.removeAll()
    }

    func addFSAccessMountSession(_ session: FSAccessMountSession) {
        fsAccessMountSessions[session.id] = session
    }

    func removeFSAccessMountSession(sessionId: UUID) {
        if let session = fsAccessMountSessions.removeValue(forKey: sessionId) {
            session.setMountChannel(nil)
        }
        // 해당 session 에 묶인 stream routes 도 정리.
        let toRemove = fsAccessStreamRoutes.filter { $0.value.mountSessionId == sessionId }.map(\.key)
        for transferId in toRemove {
            fsAccessStreamRoutes.removeValue(forKey: transferId)
        }
    }

    func fsAccessMountSession(forId sessionId: UUID) -> FSAccessMountSession? {
        return fsAccessMountSessions[sessionId]
    }

    // MARK: - fsaccess stream routes

    func addFSAccessStreamRoute(_ route: FSAccessStreamRoute) {
        fsAccessStreamRoutes[route.transferId] = route
    }

    func removeFSAccessStreamRoute(transferId: UUID) {
        fsAccessStreamRoutes.removeValue(forKey: transferId)
    }

    func fsAccessStreamRoute(forTransferId transferId: UUID) -> FSAccessStreamRoute? {
        return fsAccessStreamRoutes[transferId]
    }

    func abortFSAccessStreamRoutes(forMountSession sessionId: UUID) {
        let toRemove = fsAccessStreamRoutes.filter { $0.value.mountSessionId == sessionId }.map(\.key)
        for transferId in toRemove {
            fsAccessStreamRoutes.removeValue(forKey: transferId)
        }
    }

    // MARK: - fsaccess mount consent UI

    /// UI 가 사용자 결정을 보고할 때 호출. 현재 active continuation 을 깨운다.
    func resolveFSAccessConsent(_ decision: FSAccessConsentDecision) {
        guard let cont = activeFSAccessConsentContinuation else {
            logger.warning("resolveFSAccessConsent called with no active continuation")
            return
        }
        activeFSAccessConsentContinuation = nil
        activeFSAccessConsentRequest = nil
        cont.resume(returning: decision)
        presentNextFSAccessConsentIfNeeded()
    }

    private func presentNextFSAccessConsentIfNeeded() {
        guard activeFSAccessConsentRequest == nil else { return }
        guard !pendingFSAccessConsents.isEmpty else { return }
        let (request, cont) = pendingFSAccessConsents.removeFirst()
        activeFSAccessConsentRequest = request
        activeFSAccessConsentContinuation = cont
    }

    fileprivate func enqueueFSAccessConsent(_ request: FSAccessConsentRequest) async -> FSAccessConsentDecision {
        return await withCheckedContinuation { (cont: CheckedContinuation<FSAccessConsentDecision, Never>) in
            pendingFSAccessConsents.append((request, cont))
            presentNextFSAccessConsentIfNeeded()
        }
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
        default:
            return projectionError.localizedDescription
        }
    }
}

// MARK: - FSAccessConsentBroker

extension RemoteSession: FSAccessConsentBroker {
    @MainActor
    func requestConsent(_ request: FSAccessConsentRequest) async -> FSAccessConsentDecision {
        return await enqueueFSAccessConsent(request)
    }
}
