//
//  NoctilucaClient.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 11/29/25.
//

import Foundation
import Combine

import SiriusKitClient

enum NoctilucaClientError: LocalizedError {
    case unsupportedProtocolVersion
    case invalidPhase
    
    case remoteClosedConnection
    case authNegotiationFailed(authMethods: [ClientAuthMethod])
    
    var errorDescription: String? {
        switch self {
        case .unsupportedProtocolVersion:
            return "지원하지 않는 프로토콜 버전입니다."
        case .invalidPhase:
            return "잘못된 페이즈 전환이 시도되었습니다."
        case .remoteClosedConnection:
            return "호스트가 임의로 연결을 종료했습니다."
        case .authNegotiationFailed(let authMethods):
            if authMethods.isEmpty {
                return "인증 방법 협상에 실패했습니다.\n서버에서 아무런 인증 방법도 제시하지 않았습니다."
            }
            
            let joined = authMethods.map { $0.rawValue }.joined(separator: ", ")
            return "인증 방법 협상에 실패했습니다.\n서버에서 인증 방법으로 \(joined)를 제시했지만, 현재 버전의 클라이언트에서는 이 중 아무것도 지원하지 않습니다."
        }
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

enum NoctilucaClientUIEvent: Sendable {
    case receivedAuthChallenge(AuthChallenge)
    case receivedAuthResponse(AuthResponse)
    case phaseChanged(NoctilucaClientPhase)
    case errorOccurred(NoctilucaClientError)
    
    case pingRTTUpdated(TimeInterval)
    
    case FIXME_projectionStarted(ProjectionSession)

    case inputWarningUpdated(InputWarning?)
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
    let logger = SiriusLogger(category: "NoctilucaClient", subsystem: "pl.unstabler.noctiluca.NoctilucaClient")
    
    let id: UUID = UUID()

    let session: SiriusClient
    let authenticator: ClientAuthenticator
    let uiEvents = PassthroughSubject<NoctilucaClientUIEvent, Never>()
    
    private var pingTask: Task<Void, Never>?
    private var pongHandler: (() -> Void)?
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
    
    var hidioController: HIDIOController!
    var projectionChannel: ProjectionChannel!

    var pendingInputRedirectionMethod: AppSettings.InputRedirectionMethod = .gameController

    var sessionSettings: SessionSettings? = nil

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
    
    func setup() async throws {
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
    }
    
    private func pingLoop() async {
        self.pingRTTSamples.reserveCapacity(10)
        
        do {
            while !Task.isCancelled {
                let startTime = Date()
                await withCheckedContinuation { continuation in
                    self.pongHandler = {
                        self.pongHandler = nil
                        
                        continuation.resume()
                    }
                    
                    Task {
                        try await self.mainChannel.sendPing()
                    }
                }
                let endTime = Date()
                
                let rtt = endTime.timeIntervalSince(startTime)
                self.pingRTTSamples.append(rtt)
                
                await MainActor.run {
                    self.uiEvents.send(.pingRTTUpdated(self.averagePingRTT))
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
    
    func close() async {
        guard self.phase != .closed else {
            return
        }
        
        self.phase = .closed

        self.hidioController?.disconnectAll(kind: .keyboard)
        self.hidioController?.disconnectAll(kind: .mouse)
        self.hidioController?.disconnectAll(kind: .pointer)

        // self.phaseShiftAssertionTask?.cancel()
        self.eventLoopTask?.cancel()
        
        await self.session.shutdown()
    }
}


extension NoctilucaClient: SiriusClientDelegate {
    func siriusClientDidCloseTransport(_ client: SiriusKitClient.SiriusClient) {
        Task {
            await MainActor.run {
                self.uiEvents.send(.errorOccurred(.remoteClosedConnection))
            }
            await self.close()
        }
    }
    
    func siriusClient(_ client: SiriusClient, didCreateMainChannel mainChannel: MainChannel) {
        self.mainChannel = mainChannel
        self.eventLoopTask = Task {
            await mainChannelEventLoop()
        }
        self.pingTask = Task {
            await pingLoop()
        }
        
        Task {
            try await self.sendClientHello()
        }
    }
}
