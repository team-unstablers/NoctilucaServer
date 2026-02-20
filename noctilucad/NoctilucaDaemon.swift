//
//  NoctilucaDaemon.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/20/26.
//

import Foundation
import ArgumentParser

import SiriusKit

/// noctilucad가 어떤 스코프로 실행되었는지 나타냅니다.
enum DaemonScope: String, ExpressibleByArgument, CaseIterable {
    /// 글로벌을 타겟으로 실행되었습니다.
    /// 단, uid가 항상 0이라는 보장은 없습니다.
    case global
    
    /// 사용자 스코프로 실행되었습니다.
    case user
    
    static func determine() -> Self {
        return getuid() == 0 ? .global : .user
    }
}

class NoctilucaDaemon {
    private let logger = NoctilucaLogger(category: "NoctilucaDaemon")
    let scope: DaemonScope
    
    private let agentRegistry = AgentRegistry()
    private let xpcService: DaemonXPCService
    
    private(set) var settings: DaemonSettings = .init()

    init(scope: DaemonScope) {
        self.scope = scope
        
        self.xpcService = DaemonXPCService(agentRegistry: agentRegistry)
    }
    
    /// 설정을 로드하고, 뭔가 준비한다
    func prepare() {
        do {
            self.settings = try DaemonSettings.load(scope: scope)
        } catch {
            self.logger.error("failed to load settings: \(error)")
        }
        
    }
    
    func start() {
        xpcService.start()
        
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
    }
}
