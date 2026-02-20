//
//  NoctilucaDaemon.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/20/26.
//

import Foundation
import ArgumentParser

import SiriusKit
import NoctilucaPluginKit

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
    private var settingsXPCService: SettingsXPCService!

    /// 설정 접근을 직렬화하기 위한 큐.
    /// XPC 핸들러에서 설정을 동시에 읽기/쓰기할 수 있으므로 직렬 큐로 보호한다.
    private let settingsQueue = DispatchQueue(label: "noctilucad.settings")
    private var settings: DaemonSettings = .init()

    init(scope: DaemonScope) {
        self.scope = scope

        self.xpcService = DaemonXPCService(agentRegistry: agentRegistry)
        self.settingsXPCService = SettingsXPCService(daemon: self)
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
        settingsXPCService.start()

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

    // MARK: - Settings Access (Thread-Safe)

    /// 현재 설정의 스냅샷을 반환한다.
    func readSettings() -> DaemonSettings {
        settingsQueue.sync { settings }
    }

    /// 새 설정을 디스크에 저장하고 인메모리 상태를 갱신한다.
    ///
    /// 기존 ``Security.allowedEntries``는 호출자가 보존 책임을 진다.
    func applySettings(_ newSettings: DaemonSettings) throws {
        try settingsQueue.sync {
            try newSettings.save(scope: scope)
            self.settings = newSettings
        }
    }

    /// AuthEntry를 추가하고 Keychain에 저장한다.
    func addAuthEntry(_ entry: AuthEntry) throws {
        try settingsQueue.sync {
            settings.security.allowedEntries.append(entry)
            try settings.save(scope: scope)
        }
    }

    /// AuthEntry를 method + identifier로 식별하여 제거하고 Keychain에 저장한다.
    ///
    /// - Returns: 실제로 제거된 엔트리가 있으면 `true`
    @discardableResult
    func removeAuthEntry(method: AuthMethod, identifier: String) throws -> Bool {
        try settingsQueue.sync {
            let countBefore = settings.security.allowedEntries.count
            settings.security.allowedEntries.removeAll { entry in
                entry.method == method && entry.identifier == identifier
            }

            let removed = settings.security.allowedEntries.count < countBefore

            if removed {
                try settings.save(scope: scope)
            }

            return removed
        }
    }
}
