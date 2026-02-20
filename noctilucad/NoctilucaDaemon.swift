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

    // MARK: - QUIC Server

    let featureProvider = DaemonFeatureProvider()
    let authPluginRegistry = AuthPluginRegistry.shared
    let pluginBundleRegistry = PluginBundleRegistry.shared
    let authenticator: Authenticator

    private var server: SiriusServer?
    private var daemonSessions: [UUID: DaemonClientSession] = [:]

    /// 설정 접근을 직렬화하기 위한 큐.
    /// XPC 핸들러에서 설정을 동시에 읽기/쓰기할 수 있으므로 직렬 큐로 보호한다.
    private let settingsQueue = DispatchQueue(label: "noctilucad.settings")
    private var settings: DaemonSettings = .init()

    init(scope: DaemonScope) {
        self.scope = scope

        self.authenticator = Authenticator(registry: authPluginRegistry)
        self.xpcService = DaemonXPCService(agentRegistry: agentRegistry)
        self.settingsXPCService = SettingsXPCService(daemon: self)
    }

    /// 설정을 로드하고, 인증 플러그인을 준비한다.
    func prepare() async {
        // 1. 설정 로드
        do {
            self.settings = try DaemonSettings.load(scope: scope)
        } catch {
            self.logger.error("failed to load settings: \(error)")
        }

        let settings = readSettings()

        // 2. 인증 플러그인 등록
        pluginBundleRegistry.configure(policy: settings.security.pluginBundleSecurityPolicy)

        do {
            try await pluginBundleRegistry.registerBuiltinBundles()
        } catch {
            self.logger.error("failed to register builtin bundles: \(error)")
        }

        if settings.security.pluginBundleSecurityPolicy != .disallowAll {
            await pluginBundleRegistry.loadExternalBundles()
        }

        // 3. 인증 엔트리 설정
        await authenticator.setupAllowedEntires(settings.security.allowedEntries)
    }

    func start() async throws {
        xpcService.start()
        settingsXPCService.start()

        var settings = readSettings()

        
        // TLS 아이덴티티 로드
        if settings.quicTransport.identity == nil {
            try settings.quicTransport.autoconfigureIdentity()
            try settings.save(scope: scope)
        }
        
        
        guard let identity = settings.quicTransport.identity else {
            logger.error("No TLS identity configured. QUIC server will not start.")
            return
        }

        let identitySource = identity.identitySource

        // SiriusServer 빌드 (QUIC 트랜스포트)
        let result = SiriusServerBuilder()
            .useFeatureProvider(featureProvider)
            .useTransportProtocol(.quic(
                implementation: settings.transport.implementation,
                port: settings.quicTransport.listenPort,
                identitySource: identitySource
            ))
            .build()

        switch result {
        case .success(let server):
            self.server = server
            server.delegate = self

            try await server.setup()
            try await server.startup()

            logger.info("QUIC server started on port \(settings.quicTransport.listenPort)")

        case .failure(let error):
            logger.error("Failed to build SiriusServer: \(error)")
            throw error
        }
    }

    func shutdown() async {
        if let server {
            do {
                try await server.shutdown()
            } catch {
                logger.error("Failed to shutdown SiriusServer: \(error)")
            }
            self.server = nil
        }

        let sessions = daemonSessions.values
        for session in sessions {
            await session.close()
        }
        daemonSessions.removeAll()
    }

    // MARK: - Daemon Session Management

    func removeDaemonSession(id: UUID) {
        daemonSessions.removeValue(forKey: id)
    }

    /// DaemonClientSession이 인증 완료 후 에이전트에 핸드오프할 때 호출한다.
    func handoffToAgent(
        daemonSession: DaemonClientSession,
        uid: uid_t,
        metadata: SiriusXPCAuthMetadata,
        mainChannelStream: SiriusKitCore.Stream
    ) {
        guard let agent = agentRegistry.agentWithFallback(for: uid) else {
            logger.error("No agent found for uid \(uid), disconnecting client")
            Task { await daemonSession.close() }
            return
        }

        let clientID = daemonSession.session.id
        let agentUID = agent.uid
        let proxy = XPCTransportProxy(
            clientID: clientID,
            transport: daemonSession.session.transport as! any ServerRoleClientTransport,
            agentProxy: agent.proxy
        )

        // 연결 종료 시 AgentRegistry에서 프록시 정리
        proxy.onClose = { [weak self] closedClientID in
            self?.agentRegistry.unregisterClientProxy(clientID: closedClientID, for: agentUID)
            self?.logger.info("Client proxy \(closedClientID) cleaned up from agent uid=\(agentUID)")
        }

        agentRegistry.registerClientProxy(proxy, for: agentUID)

        // 에이전트에 사전 인증 클라이언트 전달
        agent.proxy.acceptPreAuthenticatedClient(
            clientID as NSUUID,
            metadata: metadata
        ) { [weak self] accepted in
            guard let self else { return }

            guard accepted else {
                self.logger.error("Agent rejected client \(clientID)")
                self.agentRegistry.unregisterClientProxy(clientID: clientID, for: agent.uid)
                return
            }

            // MainChannel 스트림 프록시 시작
            proxy.startProxying(mainChannelStream: mainChannelStream)

            // transport delegate를 XPCTransportProxy로 교체
            daemonSession.session.replaceTransportDelegate(proxy)

            self.logger.info("Client \(clientID) handed off to agent uid=\(agent.uid)")
        }

        // 데몬 세션 정리
        daemonSessions.removeValue(forKey: daemonSession.session.id)
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

// MARK: - SiriusServerDelegate

extension NoctilucaDaemon: SiriusServerDelegate {
    func siriusServerDidStart(_ server: SiriusServer) {
        logger.info("QUIC server is now listening")
    }

    func siriusServerDidStop(_ server: SiriusServer) {
        logger.info("QUIC server stopped")
    }

    func siriusServer(_ server: SiriusServer, didEncounterError error: any Error) {
        logger.error("QUIC server error: \(error)")
    }

    func siriusServerDidAcceptClientSession(_ server: SiriusServer, session: ClientSession) {
        logger.info("Accepted new client connection: \(session.id)")

        let daemonSession = DaemonClientSession(session: session, daemon: self)
        daemonSessions[session.id] = daemonSession
        daemonSession.start()
    }

    func siriusServerDidFailToAcceptClientSession(_ server: SiriusServer, error: any Error) {
        logger.error("Failed to accept client session: \(error)")
    }
}
