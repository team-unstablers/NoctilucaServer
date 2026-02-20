//
//  DaemonClientSession.swift
//  noctilucad
//
//  Created by Claude on 2/20/26.
//

import Foundation

import SiriusKit
import SiriusKitCore
import NoctilucaPluginKit

struct ClientInfo {
    let agentName: String
    let protocolVersion: SiriusProtocolVersion
}

enum NoctilucaClientSessionError: LocalizedError {
    case unsupportedProtocolVersion
    case invalidPhase
}

enum NoctilucaClientSessionPhase {
    /// 연결 직후. 아직 ClientHello를 받지 않은 상태.
    case initial
    
    /// ClientHello를 받고, ServerHello 및 AuthChallenge를 보낸 상태.
    case awaitingAuthentication
    
    /// 인증이 완료되어 세션이 할당된 상태.
    case ready
    
    /// 치명적인 오류가 발생되어 곧 세션이 종료될 상태.
    case panic
    
    /// 세션이 종료된 상태.
    case closed
    
    var allowedTransitions: Set<NoctilucaClientSessionPhase> {
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



/// 데몬 측 클라이언트 세션. MainChannel 핸드셰이크/인증만 처리하고,
/// 인증 완료 후 에이전트에 핸드오프한다.
///
/// `NoctilucaClientSession+Auth.swift`의 데몬 버전이다.
class DaemonClientSession {
    private let logger = NoctilucaLogger(category: "DaemonClientSession")

    let session: ClientSession
    let daemon: NoctilucaDaemon

    var mainChannel: MainChannel!

    private(set) var phase: Phase = .initial

    var clientInfo: ClientInfo?
    var remoteAddress: String

    var authNonce: Data?
    var loginAttempts: Int = 0

    private var eventLoopTask: Task<Void, Never>?
    private var phaseShiftAssertionTask: Task<Void, Never>?

    enum Phase: Equatable {
        case initial
        case awaitingAuthentication
        case handedOff
        case closed

        static func == (lhs: Phase, rhs: Phase) -> Bool {
            switch (lhs, rhs) {
            case (.initial, .initial),
                (.awaitingAuthentication, .awaitingAuthentication),
                (.handedOff, .handedOff),
                (.closed, .closed):
                return true
            default:
                return false
            }
        }
    }

    init(session: ClientSession, daemon: NoctilucaDaemon) {
        self.session = session
        self.daemon = daemon
        self.remoteAddress = session.remoteEndpoint?.description ?? "(unknown)"
    }

    func start() {
        session.delegate = self
        startPhaseShiftAssertion(expect: .awaitingAuthentication, within: 5)
    }

    // MARK: - MainChannel Event Loop

    private func mainChannelEventLoop() async {
        do {
            for await event in mainChannel.events {
                switch event {
                case .receivedClientHello(let message):
                    try await handleClientHello(message)
                case .receivedAuthRequest(let message):
                    try await handleAuthRequest(message)
                case .receivedGoodbye(let message):
                    logger.info("[\(self.session.id)] Received Goodbye: code=\(message.code.rawValue)")
                    await close()
                    return
                case .receivedPing:
                    try await mainChannel.sendPong()
                default:
                    break
                }
            }
        } catch {
            logger.error("[\(self.session.id)] Error in event loop: \(error)")
        }

        // 핸드오프 완료된 세션은 닫지 않는다 (transport가 에이전트에 넘어감)
        guard phase != .handedOff else { return }
        await close()
    }

    // MARK: - Handshake

    func handleClientHello(_ message: ClientHello) async throws {
        try assertPhase(expected: .initial)
        logger.debug("[\(self.session.id)] ClientHello from \(message.agentName), protocol \(message.protocolVersion)")

        guard message.protocolVersion == .v1_0 else {
            logger.error("[\(self.session.id)] Unsupported protocol version: \(message.protocolVersion)")
            await closeWithGoodbye(code: .protocolError, message: "Unsupported protocol version")
            return
        }

        self.clientInfo = ClientInfo(
            agentName: message.agentName,
            protocolVersion: message.protocolVersion
        )
        self.phase = .awaitingAuthentication

        let settings = daemon.readSettings()

        // ServerHello
        let supportedFeatures: [UUID] = if !settings.transport.disableSupportedFeaturesAnnouncement {
            daemon.featureProvider.supportedFeatures().map(\.rawValue)
        } else {
            []
        }

        let serverName: String = if !settings.transport.disableServerVersionAnnouncement {
            "\(NoctilucaMeta.productName)/\(NoctilucaMeta.version)"
        } else {
            NoctilucaMeta.productName
        }

        try await mainChannel.sendServerHello(ServerHello(
            protocolVersion: .v1_0,
            supportedFeatures: supportedFeatures,
            serverName: serverName,
            motd: settings.transport.motd.isEmpty ? nil : settings.transport.motd
        ))

        // AuthChallenge
        let nonce = generateNonce()
        self.authNonce = nonce

        try await mainChannel.sendAuthChallenge(AuthChallenge(
            acceptedMethods: daemon.authenticator.supportedMethods().map(\.rawValue),
            nonce: nonce,
            message: settings.transport.authChallengeMessage.isEmpty
                ? nil : settings.transport.authChallengeMessage
        ))

        startPhaseShiftAssertion(expect: .handedOff, within: 60)
    }

    // MARK: - Authentication

    func handleAuthRequest(_ message: consuming AuthRequest) async throws {
        try assertPhase(expected: .awaitingAuthentication)
        logger.debug("[\(self.session.id)] AuthRequest with method: \(message.method)")

        let method = AuthMethod(rawValue: message.method)
        guard daemon.authenticator.supports(method: method) else {
            try? await sendNotice(.error, code: .unsupportedAuthMethod)
            try await authFailure()
            return
        }

        guard let authNonce = self.authNonce, message.nonce == authNonce else {
            try? await sendNotice(.error, code: .nonceDismatch)
            try await authFailure()
            return
        }

        let result = await daemon.authenticator.authenticate(
            using: method, payload: message.payload, nonce: authNonce
        )

        switch result {
        case .success(let uid):
            logger.info("[\(self.session.id)] Authentication succeeded, uid=\(uid)")

            try await mainChannel.sendAuthResponse(AuthResponse(sessionID: session.id))

            // 핸드오프
            performHandoff(uid: uid)

        case .failure(let error):
            logger.error("[\(self.session.id)] Authentication failed: \(error)")
            try await authFailure()
        }
    }

    /// 인증 실패 처리. 지연 후 재챌린지하거나, 최대 시도 초과 시 연결을 끊는다.
    private func authFailure() async throws {
        let seconds = max(3 * UInt64(loginAttempts + 1), 10)
        try? await Task.sleep(for: .seconds(seconds))

        loginAttempts += 1

        let settings = daemon.readSettings()
        guard loginAttempts < settings.security.maxLoginAttempts else {
            logger.warning("[\(self.session.id)] Max login attempts exceeded")
            await closeWithGoodbye(code: .authenticationFailed, message: "Maximum login attempts exceeded")
            return
        }

        let nonce = generateNonce()
        self.authNonce = nonce

        try await mainChannel.sendAuthChallenge(AuthChallenge(
            acceptedMethods: daemon.authenticator.supportedMethods().map(\.rawValue),
            nonce: nonce,
            message: settings.transport.authChallengeMessage.isEmpty
                ? nil : settings.transport.authChallengeMessage
        ))

        startPhaseShiftAssertion(expect: .handedOff, within: 60)
    }

    // MARK: - Handoff

    private func performHandoff(uid: uid_t) {
        // 1. MainChannel에서 스트림 분리 (이벤트 루프 중단)
        let detachedStream = mainChannel.detachStream()

        // 2. 메타데이터 생성
        let metadata = SiriusXPCAuthMetadata(
            sessionID: session.id,
            agentName: clientInfo?.agentName ?? "",
            protocolVersionRaw: clientInfo?.protocolVersion.rawValue ?? SiriusProtocolVersion.v1_0.rawValue,
            remoteAddress: remoteAddress
        )

        // 3. 이벤트 루프 중단
        eventLoopTask?.cancel()
        eventLoopTask = nil
        phaseShiftAssertionTask?.cancel()
        phaseShiftAssertionTask = nil

        self.phase = .handedOff

        // 4. 데몬에 핸드오프 요청
        daemon.handoffToAgent(
            daemonSession: self,
            uid: uid,
            metadata: metadata,
            mainChannelStream: detachedStream
        )
    }

    // MARK: - Lifecycle

    func close() async {
        guard phase != .closed else { return }
        phase = .closed

        phaseShiftAssertionTask?.cancel()
        eventLoopTask?.cancel()

        await session.close()
        daemon.removeDaemonSession(id: session.id)
    }

    func closeWithGoodbye(code: ClosureCode, message: String? = nil) async {
        guard phase != .closed else { return }

        do {
            try await mainChannel?.sendGoodbye(Goodbye(code: code, message: message))
            try? await Task.sleep(for: .milliseconds(100))
        } catch {
            logger.warning("[\(self.session.id)] Failed to send Goodbye: \(error)")
        }

        await close()
    }

    // MARK: - Helpers

    func assertPhase(expected: Phase) throws {
        guard phase == expected else {
            logger.error("[\(self.session.id)] Expected phase \(expected), got \(self.phase)")
            throw DaemonClientSessionError.invalidPhase
        }
    }

    func startPhaseShiftAssertion(expect phase: Phase, within seconds: UInt64) {
        phaseShiftAssertionTask?.cancel()
        phaseShiftAssertionTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return
            }

            guard let self, self.phase != phase else { return }
            self.logger.error("[\(self.session.id)] Phase shift timeout: expected \(phase) within \(seconds)s")
            await self.closeWithGoodbye(code: .protocolError, message: "Phase shift timeout")
        }
    }

    private func generateNonce() -> Data {
        var nonce = Data(count: 32)
        let result = nonce.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        precondition(result == errSecSuccess, "Failed to generate random nonce")
        return nonce
    }

    private func sendNotice(_ severity: NoticeSeverity, code: ServerNoticeCode, message: String? = nil) async throws {
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        let defaultMessage = switch code {
        case .unsupportedAuthMethod: "Unsupported authentication method"
        case .nonceDismatch: "Nonce mismatch"
        case .timeout: "Timeout"
        default: "Server notice"
        }

        try await mainChannel.sendServerNotice(ServerNotice(
            severity: severity,
            code: code.rawValue,
            message: message ?? defaultMessage,
            timestamp: timestamp
        ))
    }
}

// MARK: - Error

enum DaemonClientSessionError: Error {
    case invalidPhase
}

// MARK: - ClientSessionDelegate

extension DaemonClientSession: ClientSessionDelegate {
    func clientSessionDidCloseTransport(_ session: ClientSession) {
        Task { await close() }
    }

    func clientSessionDidCreateMainChannel(_ session: ClientSession, mainChannel: MainChannel) {
        self.mainChannel = mainChannel
        self.eventLoopTask = Task { await mainChannelEventLoop() }
    }
}
