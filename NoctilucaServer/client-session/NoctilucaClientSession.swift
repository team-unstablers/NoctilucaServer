//
//  NoctilucaClientSession.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import Foundation
import SiriusKit

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

protocol NoctilucaClientSessionDelegate: AnyObject {
    func noctilucaClientSessionDidClose(_ session: NoctilucaClientSession)
}

class NoctilucaClientSession: Identifiable {
    let logger = SiriusLogger(category: "NoctilucaClientSession", subsystem: "app.noctiluca.server")
    
    var id: UUID { session.id }
    
    let session: ClientSession
    let server: ServerContext
    
    var mainChannel: MainChannel!
    
    weak var delegate: NoctilucaClientSessionDelegate?

    private(set) var phase: NoctilucaClientSessionPhase = .initial
    
    var clientInfo: ClientInfo? = nil
    var remoteAddress: String
    
    var authNonce: Data? = nil
    var loginAttempts: Int = 0
    
    private var eventLoopTask: Task<Void, Never>?
    private var phaseShiftAssertionTask: Task<Void, Never>?
    private var didNotifyClose: Bool = false
    
    init(session: ClientSession, server: ServerContext) {
        self.session = session
        self.server = server
        self.remoteAddress = "(unknown)"

        self.session.delegate = self
    }

    /// XPC 프록시를 통해 사전 인증된 클라이언트 세션을 생성한다.
    ///
    /// noctilucad가 MainChannel 핸드셰이크/인증을 완료한 후 에이전트에 전달한 메타데이터를 사용하여
    /// `.ready` 상태로 직행한다. 핸드셰이크/인증 절차는 생략된다.
    convenience init(session: ClientSession, server: ServerContext, preAuthenticated metadata: SiriusXPCAuthMetadata) {
        self.init(session: session, server: server)
        self.clientInfo = ClientInfo(
            agentName: metadata.agentName,
            protocolVersion: SiriusProtocolVersion(rawValue: metadata.protocolVersionRaw)
        )
        self.remoteAddress = metadata.remoteAddress
        self.phase = .ready
        self.session.shouldAcceptChannelCreation = true
    }
    
    func initialize() {
        guard self.phase == .initial else {
            // pre-authenticated 모드 (.ready)인 경우 타이머 불필요
            logger.info("initialize() skipped: phase is already \(self.phase)")
            return
        }
        
        self.remoteAddress = session.remoteEndpoint?.description ?? "(unknown)"
        
        // 우선 5초 이내에 client hello를 받아야 한다
        // TODO: 이 값은 설정 가능하도록 한다
        self.startPhaseShiftAssertion(expect: .awaitingAuthentication, within: 5)
    }
    
    private func mainChannelEventLoop() async {
        do {
            for await event in mainChannel.events {
                switch event {
                case .receivedClientHello(let message):
                    try await handleClientHello(message)
                case .receivedAuthRequest(let message):
                    try await handleAuthRequest(message)
                case .receivedGoodbye(let message):
                    logger.info("Received Goodbye from client: code=\(message.code.rawValue), message=\(message.message ?? "(none)")")
                    // Goodbye 수신 시에는 재전송 없이 정리만 수행
                    await self.close()
                    return
                case .receivedPing:
                    try await self.mainChannel.sendPong()
                default:
                    // ignore other events
                    break
                }
            }
        } catch NoctilucaClientSessionError.invalidPhase {
            // 잘못된 페이즈의 메시지를 보냈으므로 접속을 끊는게 맞다
            await self.close()
        } catch {
            // 예상치 못한 오류
            await self.panic("Error in mainChannelEventLoop: \(error)")
        }

        // 메인 채널 이벤트 루프 종료 시 정리
        await self.close()
    }
    
    /// noctilucad에 의해 사전 인증된 세션 전용 메인 채널 이벤트 루프.
    ///
    /// 핸드셰이크/인증 메시지(ClientHello, AuthRequest)는 이미 데몬에서 처리되었으므로,
    /// keepalive(Ping/Pong)와 Goodbye만 처리한다.
    private func mainChannelPostAuthEventLoop() async {
        do {
            for await event in mainChannel.events {
                switch event {
                case .receivedPing:
                    try await self.mainChannel.sendPong()
                case .receivedGoodbye(let message):
                    logger.info("Received Goodbye from client: code=\(message.code.rawValue), message=\(message.message ?? "(none)")")
                    await self.close()
                    return
                default:
                    break
                }
            }
        } catch {
            await self.panic("Error in mainChannelPostAuthEventLoop: \(error)")
        }

        await self.close()
    }

    @inline(__always) // 이게 효과가 있을지?
    func assertPhase(expected: NoctilucaClientSessionPhase) throws {
        guard self.phase == expected else {
            logger.error("assertPhase(): Expected phase \(expected), but current phase is \(self.phase)")
            throw NoctilucaClientSessionError.invalidPhase
        }
    }
    
    /// Phase 전환을 시도한다.
    func shiftPhase(to newPhase: NoctilucaClientSessionPhase) throws {
        logger.debug("shiftPhase(): Transitioning phase from \(self.phase) to \(newPhase)")
        
        guard self.phase.allowedTransitions.contains(newPhase) else {
            logger.error("shiftPhase(): Phase transition from \(self.phase) to \(newPhase) is not allowed")
            throw NoctilucaClientSessionError.invalidPhase
        }
        
        if newPhase == .ready {
            // 인증 완료된 상태이므로 추가 채널을 만들 수 있도록 한다.
            self.session.shouldAcceptChannelCreation = true
            
            Task {
                // 인증 완료되었으므로 빠르게 재접속할 수 있게 티켓을 발행한다
                await self.session.issueResumeTicket()
            }
        }
        
        self.phase = newPhase
    }
    
    /// 주어진 시간 내에 Phase 전환이 이루어질 것임을 assert한다.
    /// assert에 실패하면 접속을 끊는다.
    ///
    /// NOTE: 중첩된 경우, 기존 것을 취소하고 새로 시작한다.
    func startPhaseShiftAssertion(expect phase: NoctilucaClientSessionPhase, within seconds: UInt64) {
        self.phaseShiftAssertionTask?.cancel()

        self.phaseShiftAssertionTask = Task {
            do {
                try await Task.sleep(for: .seconds(seconds))
            } catch {
                // interrupted
                return
            }

            if self.phase != phase {
                self.logger.fatal("Phase shift assertion failed: expected phase \(phase) within \(seconds) seconds, but current phase is \(self.phase)")
                await self.closeWithGoodbye(code: .protocolError, message: "Phase shift timeout")
            }
        }
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

        await self.closeWithGoodbye(code: .protocolError, message: reason)
    }
    
    /// Goodbye 메시지를 전송하고 연결을 종료한다.
    func closeWithGoodbye(code: ClosureCode, message: String? = nil) async {
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

        if self.phase == .ready {
            Task { @MainActor in
                AppNotification.connectionClosed(endpoint: remoteAddress).post()
            }
        }

        self.phase = .closed
        self.notifyCloseIfNeeded()

        let channels = await self.session.channelManager.channels
        for channel in channels.values {
            if let projectionChannel = channel as? ProjectionChannel {
                await projectionChannel.destroy()
            }
        }

        self.phaseShiftAssertionTask?.cancel()
        self.eventLoopTask?.cancel()

        await self.session.close()
    }

    private func notifyCloseIfNeeded() {
        guard !didNotifyClose else { return }
        didNotifyClose = true
        delegate?.noctilucaClientSessionDidClose(self)
    }
}

extension NoctilucaClientSession: ClientSessionDelegate {
    func clientSessionDidCloseTransport(_ session: SiriusKit.ClientSession) {
        Task {
            await self.close()
        }
    }
    
    func clientSessionDidCreateMainChannel(_ session: SiriusKit.ClientSession, mainChannel: MainChannel) {
        self.mainChannel = mainChannel

        if self.phase == .ready {
            // pre-authenticated 모드: 인증 관련 메시지 처리 불필요
            self.eventLoopTask = Task {
                await mainChannelPostAuthEventLoop()
            }
        } else {
            self.eventLoopTask = Task {
                await mainChannelEventLoop()
            }
        }
    }
}
