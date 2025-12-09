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
    
    var loginAttempts: Int = 0
    
    private var eventLoopTask: Task<Void, Never>?
    
    init(session: ClientSession, server: ServerContext) {
        self.session = session
        self.server = server
        
        self.session.delegate = self
    }
    
    private func mainChannelEventLoop() async {
        do {
            for await event in mainChannel.events {
                switch event {
                case .receivedClientHello(let message):
                    try await handleClientHello(message)
                case .receivedAuthRequest(let message):
                    try await handleAuthRequest(message)
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
            await self.panic("Error in mainChannelEventLoop: \(error.localizedDescription)")
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
    
    func close() async {
        self.eventLoopTask?.cancel()
#warning("아니 왜 session.close()가 없어요")
    }

    
}

extension NoctilucaClientSession: ClientSessionDelegate {
    func clientSessionDidCreateMainChannel(_ session: SiriusKit.ClientSession, mainChannel: MainChannel) {
        self.mainChannel = mainChannel
        self.eventLoopTask = Task {
            await mainChannelEventLoop()
        }
    }
}
