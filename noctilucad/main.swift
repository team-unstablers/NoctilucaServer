//
//  main.swift
//  noctilucad
//
//  Created by Gyuhwan Park on 2/20/26.
//

import Foundation
import SiriusKit
import SiriusKitCore

// FIXME: @cheesekun - PEM 파일 경로
let kDefaultCertPath = "/Library/Application Support/noctilucad/server.cert.pem"
let kDefaultKeyPath = "/Library/Application Support/noctilucad/server.key.pem"

/// noctilucad: Noctiluca 시스템 데몬
///
/// - QUIC 연결을 수락하고 MainChannel 핸드셰이크/인증을 처리한다.
/// - 인증 완료 후 UID 기반으로 적절한 NoctilucaServer(Agent)에 XPC 프록시 연결을 수립한다.
/// - 각 NoctilucaServer는 가동 시 announce, 종료 시 depart한다.

let logger = SiriusLogger(category: "noctilucad")

// MARK: - Agent Registry & XPC Service

let agentRegistry = AgentRegistry()
let xpcService = DaemonXPCService(agentRegistry: agentRegistry)

logger.info("noctilucad starting up...")
logger.info("XPC service: \(kNoctilucaDaemonMachServiceName)")

xpcService.start()

// MARK: - QUIC Server

// TODO: QUIC 서버를 시작하여 클라이언트 연결을 수락한다.
//
// 구현 시 필요한 흐름:
// 1. 시스템 설정 로드 (/Library/Application Support/noctilucad/settings.json)
// 2. PEM 파일에서 TLS 아이덴티티 로드
// 3. SiriusServerBuilder로 QUIC 서버 생성
// 4. 연결 수락 시:
//    a. MainChannel 핸드셰이크 처리 (ClientHello → ServerHello + AuthChallenge)
//    b. 인증 처리 (AuthRequest → Authenticator → AuthResponse)
//    c. UID 확정 후 AgentRegistry에서 대상 에이전트 조회
//    d. SiriusXPCAuthMetadata 생성
//    e. agentProxy.acceptPreAuthenticatedClient() 호출
//    f. XPCTransportProxy 생성 → MainChannel 스트림 포워딩 시작
//    g. transport.delegate를 XPCTransportProxy로 교체

// MARK: - Run Loop

logger.info("noctilucad is running. Waiting for agent connections...")
RunLoop.current.run()
