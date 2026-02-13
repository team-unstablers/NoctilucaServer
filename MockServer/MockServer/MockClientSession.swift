//
//  MockClientSession.swift
//  MockServer
//
//  Created by Gyuhwan Park on 2/13/26.
//

import Foundation
import SiriusKit

protocol MockClientSessionDelegate: AnyObject {
    func mockClientSessionDidClose(_ session: MockClientSession)
}

class MockClientSession: Identifiable {
    private let logger = SiriusLogger(category: "MockClientSession", subsystem: "app.noctiluca.mockserver")

    private static let authMethodIdentifier = "app.noctiluca.server.auth.simple-password"
    private static let maxLoginAttempts = 3

    var id: UUID { session.id }

    let session: ClientSession
    let projectionSource: URL

    var mainChannel: MainChannel!
    weak var delegate: MockClientSessionDelegate?

    private var phase: Phase = .initial

    private var authNonce: Data?
    private var loginAttempts: Int = 0
    private var storedPasswordHash: Data!

    private var eventLoopTask: Task<Void, Never>?
    private var phaseShiftAssertionTask: Task<Void, Never>?
    private var didNotifyClose = false

    enum Phase: Equatable {
        case initial
        case awaitingAuthentication
        case ready
        case closed
    }

    init(session: ClientSession, projectionSource: URL) {
        self.session = session
        self.projectionSource = projectionSource

        self.session.delegate = self

        // 고정 패스워드 "mock"의 bcrypt hash 미리 계산
        do {
            let passwordData = Data("mock".utf8)
            let digest = try Bcrypt.sha512(value: passwordData)
            self.storedPasswordHash = try Bcrypt.hash(password: digest)
        } catch {
            fatalError("Failed to compute bcrypt hash for mock password: \(error)")
        }
    }

    func initialize() {
        guard phase == .initial else { return }
        startPhaseShiftAssertion(expect: .awaitingAuthentication, within: 5)
    }

    // MARK: - Main Channel Event Loop

    private func mainChannelEventLoop() async {
        do {
            for await event in mainChannel.events {
                switch event {
                case .receivedClientHello(let message):
                    try await handleClientHello(message)
                case .receivedAuthRequest(let message):
                    try await handleAuthRequest(message)
                case .receivedGoodbye(let message):
                    logger.info("Received Goodbye: code=\(message.code.rawValue), message=\(message.message ?? "(none)")")
                    await close()
                    return
                case .receivedPing:
                    try await mainChannel.sendPong()
                default:
                    break
                }
            }
        } catch {
            logger.error("Error in main channel event loop: \(error)")
        }

        await close()
    }

    // MARK: - Handshake

    private func handleClientHello(_ message: ClientHello) async throws {
        guard phase == .initial else {
            logger.error("Received ClientHello in unexpected phase: \(self.phase)")
            await close()
            return
        }

        guard message.protocolVersion == .v1_0 else {
            logger.error("Unsupported protocol version: \(message.protocolVersion)")
            await closeWithGoodbye(code: .protocolError, message: "Unsupported protocol version")
            return
        }

        logger.info("Received ClientHello from \(message.agentName)")
        phase = .awaitingAuthentication

        // ServerHello 전송
        let serverHello = ServerHello(
            protocolVersion: .v1_0,
            supportedFeatures: [
                SiriusFeature.hidio.rawValue,
                SiriusFeature.projection.rawValue,
            ],
            serverName: "MockServer/1.0",
            motd: nil
        )
        try await mainChannel.sendServerHello(serverHello)

        // AuthChallenge 전송
        let nonce = generateNonce()
        self.authNonce = nonce

        let challenge = AuthChallenge(
            acceptedMethods: [Self.authMethodIdentifier],
            nonce: nonce,
            message: nil
        )
        try await mainChannel.sendAuthChallenge(challenge)

        startPhaseShiftAssertion(expect: .ready, within: 60)
    }

    // MARK: - Authentication

    private func handleAuthRequest(_ message: AuthRequest) async throws {
        guard phase == .awaitingAuthentication else {
            logger.error("Received AuthRequest in unexpected phase: \(self.phase)")
            await close()
            return
        }

        guard message.method == Self.authMethodIdentifier else {
            logger.warning("Unsupported auth method: \(message.method)")
            try await authFailure()
            return
        }

        guard let expectedNonce = self.authNonce,
              message.nonce == expectedNonce else {
            logger.warning("Nonce mismatch")
            try await authFailure()
            return
        }

        // sha512 + bcrypt 검증
        /*
        do {
            let digest = try await Bcrypt.sha512Async(value: message.payload)
            // let isValid = try await Bcrypt.verifyAsync(password: digest, hash: storedPasswordHash)

            guard isValid else {
                logger.warning("Authentication failed: password mismatch")
                try await authFailure()
                return
            }
        } catch {
            logger.error("Authentication error: \(error)")
            try await authFailure()
            return
        }
         */

        // 인증 성공
        phase = .ready
        session.shouldAcceptChannelCreation = true

        try await mainChannel.sendAuthResponse(AuthResponse(sessionID: self.id))
        logger.info("Client authenticated successfully: \(self.id)")
    }

    private func authFailure() async throws {
        let delay = max(3 * UInt64(loginAttempts + 1), 10)
        try? await Task.sleep(for: .seconds(delay))

        loginAttempts += 1

        guard loginAttempts < Self.maxLoginAttempts else {
            logger.warning("Maximum login attempts exceeded. Closing connection.")
            await closeWithGoodbye(code: .authenticationFailed, message: "Maximum login attempts exceeded")
            return
        }

        let nonce = generateNonce()
        self.authNonce = nonce

        let challenge = AuthChallenge(
            acceptedMethods: [Self.authMethodIdentifier],
            nonce: nonce,
            message: nil
        )
        try await mainChannel.sendAuthChallenge(challenge)

        startPhaseShiftAssertion(expect: .ready, within: 60)
    }

    // MARK: - Utilities

    private func generateNonce() -> Data {
        var nonce = Data(count: 32)
        let result = nonce.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!)
        }
        precondition(result == errSecSuccess, "Failed to generate random nonce")
        return nonce
    }

    private func startPhaseShiftAssertion(expect phase: Phase, within seconds: UInt64) {
        phaseShiftAssertionTask?.cancel()
        phaseShiftAssertionTask = Task {
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                return
            }

            if self.phase != phase {
                self.logger.error("Phase shift timeout: expected \(phase) within \(seconds)s, current: \(self.phase)")
                await self.closeWithGoodbye(code: .protocolError, message: "Phase shift timeout")
            }
        }
    }

    // MARK: - Teardown

    func closeWithGoodbye(code: ClosureCode, message: String? = nil) async {
        guard phase != .closed else { return }
        do {
            try await mainChannel?.sendGoodbye(Goodbye(code: code, message: message))
            try? await Task.sleep(for: .milliseconds(100))
        } catch {
            logger.warning("Failed to send Goodbye: \(error)")
        }
        await close()
    }

    func close() async {
        guard phase != .closed else { return }
        phase = .closed

        notifyCloseIfNeeded()

        // ProjectionChannel의 destroy
        let channels = await session.channelManager.channels
        for channel in channels.values {
            if let projectionChannel = channel as? MockProjectionChannel {
                await projectionChannel.destroy()
            }
        }

        phaseShiftAssertionTask?.cancel()
        eventLoopTask?.cancel()

        await session.close()
    }

    private func notifyCloseIfNeeded() {
        guard !didNotifyClose else { return }
        didNotifyClose = true
        delegate?.mockClientSessionDidClose(self)
    }
}

extension MockClientSession: ClientSessionDelegate {
    func clientSessionDidCloseTransport(_ session: ClientSession) {
        Task {
            await close()
        }
    }

    func clientSessionDidCreateMainChannel(_ session: ClientSession, mainChannel: MainChannel) {
        self.mainChannel = mainChannel
        self.eventLoopTask = Task {
            await mainChannelEventLoop()
        }
    }
}
