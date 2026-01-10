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

class NoctilucaClientSession: Identifiable {
    let logger = SiriusLogger(category: "NoctilucaClientSession", subsystem: "pl.unstabler.noctiluca.NoctilucaServer")
    
    var id: UUID { session.id }
    
    let session: ClientSession
    let server: ServerContext
    
    var mainChannel: MainChannel!
    
    private(set) var phase: NoctilucaClientSessionPhase = .initial
    
    var clientInfo: ClientInfo? = nil
    var remoteAddress: String
    
    var authNonce: Data? = nil
    var loginAttempts: Int = 0
    
    private var eventLoopTask: Task<Void, Never>?
    private var phaseShiftAssertionTask: Task<Void, Never>?
    
    init(session: ClientSession, server: ServerContext) {
        self.session = session
        self.server = server
        self.remoteAddress = "(unknown)"
        
        self.session.delegate = self
    }
    
    func initialize() {
        guard self.phase == .initial else {
            logger.warning("initialize() called, but phase is not initial. Current phase: \(self.phase)")
            return
        }
        
        self.remoteAddress = session.remoteAddress ?? "(unknown)"
        
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
                await self.close()
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
        
        // FIXME
        for channel in self.session.channelManager.channels.values {
            if channel is ProjectionChannel {
                await (channel as! ProjectionChannel).destroy()
            }
        }
        
        self.phaseShiftAssertionTask?.cancel()
        self.eventLoopTask?.cancel()
        
        await self.session.close()
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
        self.eventLoopTask = Task {
            await mainChannelEventLoop()
        }
    }
}
