//
//  NoctilucaClient.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 11/29/25.
//

import Foundation
import Combine
import Security

import SiriusKitClient

enum NoctilucaClientError: LocalizedError {
    case unsupportedProtocolVersion
    case invalidPhase
    case protocolVersionMismatch(client: String, server: String)

    case certificateValidationFailed
    case remoteClosedConnection
    case authNegotiationFailed(authMethods: [ClientAuthMethod])
    case sessionClosedByServer(ClosureCode, String?)
    case audioProjectionInitializationFailed(message: String)
    case connectionFailed(Error)

    var errorDescription: String? {
        switch self {
        case .unsupportedProtocolVersion:
            return String(localized: "error.unsupported_protocol_version", defaultValue: "지원하지 않는 프로토콜 버전입니다.")
        case .invalidPhase:
            return String(localized: "error.invalid_phase", defaultValue: "잘못된 페이즈 전환이 시도되었습니다.")
        case .protocolVersionMismatch(let client, let server):
            return String(format: String(localized: "error.protocol_version_mismatch", defaultValue: "프로토콜 버전이 호환되지 않습니다.\nClient: %@, Server: %@"), client, server)
        case .certificateValidationFailed:
            return String(localized: "error.certificate_validation_failed", defaultValue: "서버 인증서 검증에 실패했습니다.\n신뢰할 수 있는 인증서가 아니거나, 인증서가 만료되었을 수 있습니다.")
        case .remoteClosedConnection:
            return String(localized: "error.remote_closed_connection", defaultValue: "연결이 예기치 않게 끊어졌습니다.")
        case .authNegotiationFailed(let authMethods):
            if authMethods.isEmpty {
                return String(localized: "error.auth_negotiation_failed_empty", defaultValue: "인증 방법 협상에 실패했습니다.\n서버에서 아무런 인증 방법도 제시하지 않았습니다.")
            }

            let joined = authMethods.map { $0.rawValue }.joined(separator: ", ")
            return String(format: String(localized: "error.auth_negotiation_failed", defaultValue: "인증 방법 협상에 실패했습니다.\n서버에서 인증 방법으로 %@를 제시했지만, 현재 버전의 클라이언트에서는 이 중 아무것도 지원하지 않습니다."), joined)
        case .sessionClosedByServer(let code, let message):
            return Self.descriptionForClosureCode(code, message: message)
        case .audioProjectionInitializationFailed(let message):
            return String(format: String(localized: "error.audio_projection_init_failed", defaultValue: "오디오 프로젝션 초기화에 실패했습니다.\n%@"), message)
        case .connectionFailed(let error):
            return String(format: String(localized: "error.connection_failed", defaultValue: "연결에 실패했습니다.\n%@"), error.localizedDescription)
        }
    }

    var alertTitle: String {
        switch self {
        case .sessionClosedByServer(let code, _) where code == .successful:
            return String(localized: "error.alert_title.session_closed", defaultValue: "세션 종료")
        case .audioProjectionInitializationFailed:
            return String(localized: "error.alert_title.audio_connection_failed", defaultValue: "오디오 연결 실패")
        case .connectionFailed:
            return String(localized: "error.alert_title.connection_failed", defaultValue: "연결 실패")
        default:
            return String(localized: "error.alert_title.error_occurred", defaultValue: "오류 발생")
        }
    }

    private static func descriptionForClosureCode(_ code: ClosureCode, message: String?) -> String {
        let base: String
        switch code {
        case .successful:
            base = String(localized: "error.closure.successful", defaultValue: "호스트가 세션을 종료했습니다.")
        case .protocolError:
            base = String(localized: "error.closure.protocol_error", defaultValue: "프로토콜 오류로 인해 호스트가 연결을 종료했습니다.")
        case .internalServerError:
            base = String(localized: "error.closure.internal_server_error", defaultValue: "호스트 내부 오류로 인해 연결이 종료되었습니다.")
        case .authenticationFailed:
            base = String(localized: "error.closure.authentication_failed", defaultValue: "인증 실패로 인해 연결이 종료되었습니다.")
        case .sessionAllocationFailed:
            base = String(localized: "error.closure.session_allocation_failed", defaultValue: "서버의 세션 할당 실패로 인해 연결이 종료되었습니다.")
        default:
            base = String(format: String(localized: "error.closure.unknown_code", defaultValue: "호스트가 연결을 종료했습니다. (코드: %@)"), String(code.rawValue))
        }
        if let message, !message.isEmpty {
            return "\(base)\n\(message)"
        }
        return base
    }
}

enum NoctilucaClientPhase {
    /// 연결 직후. 아직 ServerHello를 받지 않은 상태.
    case initial
    
    /// ClientHello를 보내고, ServerHello 및 AuthChallenge를 받은 상태.
    case awaitingAuthentication
    
    /// 인증이 완료되어 세션이 할당된 상태.
    case ready
    
    /// 치명적인 오류가 발생되어 곧 세션이 종료될 상태.
    case panic
    
    /// 세션이 종료된 상태.
    case closed
    
    var allowedTransitions: Set<NoctilucaClientPhase> {
        switch self {
        case .initial:
            return [.awaitingAuthentication, .panic, .closed]
        case .awaitingAuthentication:
            return [.ready, .panic, .closed]
        case .ready:
            return [.closed, .panic]
        case .panic:
            return [.closed]
        case .closed:
            return []
        }
    }
}

struct SucceedValidationDecision {
    let fingerprint: Data
    let decision: ServerIdentityTrustDecision
}

enum NoctilucaClientUIEvent: Sendable {
    case receivedAuthChallenge(AuthChallenge)
    case receivedAuthResponse(AuthResponse)
    case phaseChanged(NoctilucaClientPhase)
    case errorOccurred(NoctilucaClientError)

    case pingRTTUpdated(TimeInterval)

    case channelCreated(SiriusFeature, Channel)
    case channelClosed(UUID)

    /// 서버 아이덴티티 검증이 필요합니다.
    case serverIdentityValidationNeeded(ServerIdentity)
}

struct InputWarning: Sendable, Equatable {
    enum Kind: String, Sendable {
        case inputMonitoringRequired
        case eventTapUnavailable
    }

    let kind: Kind
    let title: String
    let message: String
}

class NoctilucaClient: ObservableObject {
    let logger = SiriusLogger(category: "NoctilucaClient", subsystem: "app.noctiluca.client.logic.NoctilucaClient")
    
    let id: UUID = UUID()

    let session: SiriusClient
    let authenticator: ClientAuthenticator
    let uiEvents = PassthroughSubject<NoctilucaClientUIEvent, Never>()
    
    private var pingTask: Task<Void, Never>?
    private var pongHandler: (() -> Void)?
    private var consecutivePongMisses = 0
    private let maxConsecutivePongMisses = 3
    private(set) var pingRTTSamples: [TimeInterval] = []
    var averagePingRTT: TimeInterval {
        guard !pingRTTSamples.isEmpty else {
            return 0
        }
        
        let total = pingRTTSamples.reduce(0, +)
        return total / Double(pingRTTSamples.count)
    }
    
    
    var sessionID: UUID?
    var mainChannel: MainChannel!
    
    var hidioChannel: HIDIOChannel!
    var projectionChannel: ProjectionChannel!

    var pendingInputRedirectionMethod: AppSettings.InputRedirectionMethod = .gameController

    var sessionSettings: SessionSettings? = nil
    
    // 기존 접속으로부터 승계된 서버 아이덴티티 검증 정보
    var succeedValidationDecision: SucceedValidationDecision? = nil
    
    // 디시전 UI를 띄우기 전에 접속 종료 처리되는 것을 막기 위한 hacky한 플래그
    private(set) var isValidatingServerIdentity: Bool = false
    
    @Published
    private(set) var phase: NoctilucaClientPhase = .initial {
        didSet {
            Task {
                await MainActor.run() {
                    self.uiEvents.send(.phaseChanged(phase))
                }
            }
        }
    }

    private var eventLoopTask: Task<Void, Never>?

    init(_ session: SiriusClient) {
        self.session = session
        self.authenticator = ClientAuthenticator(registry: .shared)
        
        self.session.delegate = self
    }

    func configureAuthCredentials(sessionEntries: [ClientAuthEntry], globalEntries: [ClientAuthEntry]) {
        authenticator.configureAutoCredentials(sessionEntries: sessionEntries, globalEntries: globalEntries)
    }
    
    private func setupValidationPolicy() {
        let policy = SettingsStore.shared.settings.security.tlsValidationPolicy
        
        let validationBlock: ServerIdentityValidationBlock = { [weak self] identity in
            /// CONTEXT: 이 validation block은 시스템 트러스트 스토어 검증이 실패한 것입니다.
            guard let self = self else {
                return .deny
            }
            
            self.isValidatingServerIdentity = true
            
            // 과거로부터 '승계된' 디시전 사항이 있는지 확인합니다.
            guard let succeedDecision = self.succeedValidationDecision else {
                // 만약 없다면, 새로운 접속입니다. '이 인증서 믿을 수 없는데, 그래도 접속할래?' 따위의 UI를 표시하고, 접속을 끊어야 합니다.
                self.uiEvents.send(.serverIdentityValidationNeeded(identity))
                return .deny
            }
            
            // 승계된 디시전이 있습니다.
            defer { self.isValidatingServerIdentity = false }

            do {
                // 최소한의 검증: UI를 표시해서 디시전을 받는 그 짧은 사이에도 인증서는 바꿔 끼워질 수 있습니다.
                //              모든 것을 믿을 수 없는 어지러운 세상(乱世) 입니다.
                let currentFingerprint = try identity.fingerprint()
                guard succeedDecision.fingerprint == currentFingerprint else {
                    // TODO: 이 호스트는 수상한 행동을 합니다. 사용자에게 정말 위험하니 조심하라고 알리는 게 좋을 것 같습니다.
                    return .deny
                }
                
                // 승계된 디시전이 유효합니다. 그대로 따릅니다.
                return succeedDecision.decision
            } catch {
                // 서버 아이덴티티를 검증하는 도중에 오류가 발생했습니다. 보안을 위해 거부합니다.
                return .deny
            }
        }
        
        switch policy {
        case .default:
            session.identityValidationPolicy = .systemAndAppValidation(validationBlock)
        case .strict:
            session.identityValidationPolicy = .systemOnly
        case .unsafe:
            session.identityValidationPolicy = .dangerouslyAllowAlways
        }
    }
    
    func setup() async throws {
        self.setupValidationPolicy()
        
        await session.channelManager.setDelegate(self)
        try await session.setup()
    }
    
    func startup() async throws {
        logger.info("Starting up NoctilucaClient...")
        try await session.startup()
    }
    
    private func mainChannelEventLoop() async {
        guard mainChannel != nil else {
            logger.error("mainChannel is not initialized.")
            return
        }

        do {
            for await event in mainChannel.events {
                switch event {
                case .receivedServerHello(let message):
                    try await self.handleServerHello(consume message)
                case .receivedAuthChallenge(let message):
                    try await self.handleAuthChallenge(consume message)
                case .receivedAuthResponse(let message):
                    try await self.handleAuthResponse(consume message)
                case .receivedGoodbye(let message):
                    logger.info("Received Goodbye from server: code=\(message.code.rawValue), message=\(message.message ?? "(none)")")
                    await MainActor.run {
                        self.uiEvents.send(.errorOccurred(.sessionClosedByServer(message.code, message.message)))
                    }
                    await self.close()
                    return

                case .receivedPong:
                    self.pongHandler?()
                default:
                    break
                }
            }
        } catch NoctilucaClientError.invalidPhase {
            // 잘못된 페이즈의 메시지를 보냈으므로 접속을 끊는게 맞다
            await self.close()
        } catch {
            // 예상치 못한 오류
            await self.panic("Error in mainChannelEventLoop: \(error.localizedDescription)")
        }

        // reached end of main channel event loop
        // TODO: raise error event instead (or retry?)
        await self.close()
    }
    
    private func pingLoop() async {
        self.pingRTTSamples.reserveCapacity(10)

        do {
            while !Task.isCancelled {
                let startTime = Date()
                let didReceivePong = await pingWithTimeout()

                if didReceivePong {
                    self.consecutivePongMisses = 0
                    let rtt = Date().timeIntervalSince(startTime)
                    self.pingRTTSamples.append(rtt)

                    await MainActor.run {
                        self.uiEvents.send(.pingRTTUpdated(self.averagePingRTT))
                    }
                } else {
                    self.consecutivePongMisses += 1
                    logger.warning("Ping timeout (consecutive misses: \(self.consecutivePongMisses)/\(self.maxConsecutivePongMisses))")

                    if self.consecutivePongMisses >= self.maxConsecutivePongMisses {
                        logger.error("Connection presumed lost: \(self.consecutivePongMisses) consecutive pong timeouts")
                        await self.panic("connection lost (pong timeout)")
                        return
                    }
                }

                try await Task.sleep(for: .seconds(1))

                if self.pingRTTSamples.count >= 10 {
                    let average = self.averagePingRTT
                    self.pingRTTSamples.removeAll(keepingCapacity: true)
                    self.pingRTTSamples.append(average)
                }
            }
        } catch {
            logger.error("pingLoop() encountered error: \(error.localizedDescription)")
        }
    }

    /// Ping을 전송하고 타임아웃 내에 Pong 응답을 기다린다.
    /// AsyncStream + TaskGroup race 패턴으로 continuation leak을 방지한다.
    private func pingWithTimeout(timeoutSeconds: Double = 5.0) async -> Bool {
        let stream = AsyncStream<Void> { continuation in
            self.pongHandler = {
                self.pongHandler = nil
                continuation.yield()
                continuation.finish()
            }

            Task {
                try? await self.mainChannel.sendPing()
            }
        }

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                _ = await iterator.next()
                return true
            }

            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                return false
            }

            let result = await group.next()!
            group.cancelAll()

            if !result {
                self.pongHandler = nil
            }

            return result
        }
    }

    @inline(__always) // 이게 효과가 있을지?
    func assertPhase(expected: NoctilucaClientPhase) throws {
        guard self.phase == expected else {
            logger.error("assertPhase(): Expected phase \(expected), but current phase is \(self.phase)")
            throw NoctilucaClientError.invalidPhase
        }
    }
    
    /// Phase 전환을 시도한다.
    func shiftPhase(to newPhase: NoctilucaClientPhase) throws {
        logger.debug("shiftPhase(): Transitioning phase from \(self.phase) to \(newPhase)")
        
        guard self.phase.allowedTransitions.contains(newPhase) else {
            logger.error("shiftPhase(): Phase transition from \(self.phase) to \(newPhase) is not allowed")
            throw NoctilucaClientError.invalidPhase
        }
        
        if newPhase == .ready {
            // 인증 완료된 상태이므로 추가 채널을 만들 수 있도록 한다.
            self.session.shouldAcceptChannelCreation = true
        }
        
        self.phase = newPhase
    }
 
    /// 모든게 망했고, 당신의 꿈은 결국 이루어지지 못했습니다.
    func panic(_ reason: String) async {
        guard self.phase != .panic && self.phase != .closed else {
            // 간이 lock 역할을 한다
            return
        }

        try? self.shiftPhase(to: .panic)

        logger.fatal("panic(): \(reason)")
        logger.fatal("panic(): dropping the client session \(self.id)")

        await self.close()
    }

    /// Goodbye 메시지를 전송하고 연결을 종료한다.
    func closeWithGoodbye(code: ClosureCode = .successful, message: String? = nil) async {
        guard self.phase != .closed else { return }

        do {
            try await self.mainChannel?.sendGoodbye(Goodbye(code: code, message: message))
            // 상대방이 수신할 시간을 주기 위해 약간의 지연을 둔다
            try? await Task.sleep(for: .milliseconds(100))
        } catch {
            logger.warning("Failed to send Goodbye: \(error)")
        }

        await self.close()
    }

    func close() async {
        guard self.phase != .closed else {
            return
        }

        self.phase = .closed

        self.hidioChannel?.controller.disconnectAll(kind: .keyboard)
        self.hidioChannel?.controller.disconnectAll(kind: .mouse)
        self.hidioChannel?.controller.disconnectAll(kind: .pointer)

        // Projection 정리
        await self.projectionChannel?.stopAllSessions()

        // self.phaseShiftAssertionTask?.cancel()
        self.eventLoopTask?.cancel()
        self.pingTask?.cancel()

        await self.session.shutdown()

        await NoctilucaClientManager.shared.detachClient(id: self.id)
    }
}


extension NoctilucaClient: SiriusClientDelegate {
    func siriusClientDidCloseTransport(_ client: SiriusKitClient.SiriusClient) {
        Task {
            await self.close()
        }
    }

    func siriusClient(_ client: SiriusClient, didCreateMainChannel mainChannel: MainChannel) {
        self.mainChannel = mainChannel
        self.eventLoopTask = Task.detached(priority: .userInitiated) {
            await self.mainChannelEventLoop()
        }
        self.pingTask = Task.detached(priority: .userInitiated) {
            await self.pingLoop()
        }

        Task.detached {
            try await self.sendClientHello()
        }
    }
    
    func siriusClient(_ client: SiriusClient, didEncounterError error: any Error) {
        Task.detached {
            if let error = error as? ClientTransportError {
                self.handleTransportError(error)
                return
            }
            
            self.handleError(error)
        }
    }
    
    private func handleTransportError(_ error: ClientTransportError) {
        let error: NoctilucaClientError = switch error {
        case .certificateValidationFailed:
            .certificateValidationFailed
        default:
            .remoteClosedConnection
        }
        
        
        Task { @MainActor in
            self.uiEvents.send(.errorOccurred(error))
        }
    }
    
    private func handleError(_ error: (any Error)) {
        // TODO
    }
}


extension NoctilucaClient: ChannelManagerDelegate {
    func channelManager(_ manager: ChannelManager, didRegisterChannel channel: Channel, for feature: SiriusFeature) {
        Task { @MainActor in
            self.uiEvents.send(.channelCreated(feature, channel))
        }
    }
    
    func channelManager(_ manager: ChannelManager, willUnregisterChannel channel: Channel) {
        Task { @MainActor in
            self.uiEvents.send(.channelClosed(channel.identifier))
        }
    }
}
