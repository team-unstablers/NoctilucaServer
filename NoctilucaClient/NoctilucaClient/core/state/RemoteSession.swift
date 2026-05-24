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

#if canImport(AppKit)
import AppKit
#endif
#if canImport(UIKit)
import UIKit
#endif

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

#if os(macOS)
    private(set) var inputMethodSync: InputMethodSync? = nil
#endif

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

    @ObservationIgnored
    private var pendingFSAccessConsents: [(FSAccessConsentRequest, CheckedContinuation<FSAccessConsentDecision, Never>)] = []

    @ObservationIgnored
    private var isPresentingFSAccessConsent: Bool = false

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
#if os(macOS)
        case .simpleRPC:
            guard let simpleRPCChannel = channel as? SimpleRPCChannel else {
                return
            }
            self.inputMethodSync = InputMethodSync(self, channel: simpleRPCChannel)
#endif
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

#if os(macOS)
        if channelID == inputMethodSync?.channelID {
            // in-flight task 의 retain 으로 deinit 이 지연될 수 있으므로 nil 할당 전에
            // 명시적으로 invalidate() 해서 distributed notification observer 를 즉시 해제한다.
            inputMethodSync?.invalidate()
            self.inputMethodSync = nil
        }
#endif
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
        // 큐에 남아있는 consent 요청은 모두 deny 로 닫는다.
        // (현재 alert 로 표시 중인 요청은 사용자 입력으로 자연스럽게 resolve 되며, 그 결과는 닫힌 채널로
        // 응답이 가지 못해도 무해하다.)
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

    fileprivate func enqueueFSAccessConsent(_ request: FSAccessConsentRequest) async -> FSAccessConsentDecision {
        return await withCheckedContinuation { (cont: CheckedContinuation<FSAccessConsentDecision, Never>) in
            pendingFSAccessConsents.append((request, cont))
            Task { @MainActor in
                await drainFSAccessConsentQueueIfNeeded()
            }
        }
    }

    private func drainFSAccessConsentQueueIfNeeded() async {
        guard !isPresentingFSAccessConsent else { return }
        isPresentingFSAccessConsent = true
        defer { isPresentingFSAccessConsent = false }

        while !pendingFSAccessConsents.isEmpty {
            let (request, cont) = pendingFSAccessConsents.removeFirst()
            let decision = await presentFSAccessConsentAlert(for: request)
            cont.resume(returning: decision)
        }
    }

    private func presentFSAccessConsentAlert(for request: FSAccessConsentRequest) async -> FSAccessConsentDecision {
        let alert = NOCAlert()
        alert.title = String(localized: "fsaccess.consent.title", defaultValue: "파일 시스템 액세스 요청")
        alert.message = makeFSAccessConsentMessage(for: request)

#if canImport(AppKit)
        alert.alert.alertStyle = .warning
#endif

        var decision: FSAccessConsentDecision = .deny

        alert.addButton(title: allowAsRequestedLabel(for: request.requestedAccess)) {
            decision = .allow(grantedAccess: request.requestedAccess)
        }

        alert.addButton(title: String(localized: "common.deny", defaultValue: "거부")) {
            decision = .deny
        }

        if request.requestedAccess != .read {
            alert.addButton(title: String(localized: "fsaccess.consent.allow_read_only", defaultValue: "읽기 전용으로 허용")) {
                decision = .allow(grantedAccess: .read)
            }
        }

#if canImport(AppKit)
        // NOTE: `parent?.mainWindowController?.window` 표기는 NSWindowDelegate 의 동명 메서드와
        // 이름이 겹쳐 컴파일러가 메서드 참조로 해석하므로, 명시적으로 NSWindowController 의 window
        // 프로퍼티로 해석되도록 단계를 풀어 쓴다.
        guard let windowController = parent?.mainWindowController,
              let window: NSWindow = windowController.window else {
            logger.warning("presentFSAccessConsentAlert: no host window available; defaulting to deny")
            return .deny
        }
        await alert.present(to: window)
#elseif canImport(UIKit)
        guard let viewController = parent?.rootViewController else {
            logger.warning("presentFSAccessConsentAlert: no host view controller available; defaulting to deny")
            return .deny
        }
        await alert.present(to: viewController)
#endif

        return decision
    }

    private func makeFSAccessConsentMessage(for request: FSAccessConsentRequest) -> String {
        let subtitle = String(localized: "fsaccess.consent.subtitle", defaultValue: "원격 호스트가 이 기기의 폴더에 접근하려고 합니다.")
        let entryLabel = String(localized: "fsaccess.consent.entry", defaultValue: "폴더")
        let accessLabel = String(localized: "fsaccess.consent.requested_access", defaultValue: "요청한 권한")

        var lines: [String] = [subtitle, ""]
        lines.append("\(entryLabel): \(request.entryName)")
        lines.append("    \(request.entryPath)")
        lines.append("\(accessLabel): \(requestedAccessLabel(for: request.requestedAccess))")

        if let reason = request.reason, !reason.isEmpty {
            let reasonLabel = String(localized: "fsaccess.consent.reason", defaultValue: "사유")
            lines.append("\(reasonLabel): \(reason)")
        }

        lines.append("")
        lines.append(String(localized: "fsaccess.consent.warning_plain", defaultValue: "신뢰할 수 없는 호스트라면 거부하세요. 허용한 권한 범위 내에서 호스트는 폴더를 읽거나 수정할 수 있습니다."))

        return lines.joined(separator: "\n")
    }

    private func requestedAccessLabel(for access: AccessMode) -> String {
        switch access {
        case .read:
            return String(localized: "fsaccess.consent.access.read", defaultValue: "읽기 전용")
        case .write:
            return String(localized: "fsaccess.consent.access.write", defaultValue: "쓰기 전용")
        case .readWrite:
            return String(localized: "fsaccess.consent.access.read_write", defaultValue: "읽기/쓰기")
        default:
            return String(localized: "fsaccess.consent.access.unknown", defaultValue: "알 수 없음")
        }
    }

    private func allowAsRequestedLabel(for access: AccessMode) -> String {
        switch access {
        case .read:
            return String(localized: "fsaccess.consent.allow_read_only", defaultValue: "읽기 전용으로 허용")
        case .write:
            return String(localized: "fsaccess.consent.allow_write", defaultValue: "쓰기로 허용")
        case .readWrite:
            return String(localized: "fsaccess.consent.allow_read_write", defaultValue: "읽기/쓰기로 허용")
        default:
            return String(localized: "common.allow", defaultValue: "허용")
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
