//
//  NOCSiriusServerApplication.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import Foundation
import Combine

import SiriusKit
import NoctilucaPluginKit
import NoctilucaPluginKitHostCore

enum NoctilucaServerError: LocalizedError {
    case noIdentityConfigured
    case identityValidationFailed
    
    case invalidLicense
    
    var errorDescription: String? {
        switch self {
        case .noIdentityConfigured:
            return "No identity is configured for the server."
        case .identityValidationFailed:
            return "The configured identity failed validation."
            
        case .invalidLicense:
            return String(localized: "server.error.invalid_license", defaultValue: "시스템에 올바른 라이선스가 설치되어 있지 않습니다.")
        }
    }
}

enum NoctilucaServerState {
    case idle
    case preparing
    case running(server: SiriusServer)
}

@MainActor
final class NoctilucaServerContext: ServerContext, Sendable {
    private let server: NoctilucaServer

    var featureProvider: NoctilucaFeatureProvider { server.featureProvider }
    
    var authenticator: Authenticator { server.authenticator }
    var settings: AppSettings { SettingsStore.shared.settings }

    init(server: NoctilucaServer) {
        self.server = server
    }
    
    func serverName(withVersion: Bool) -> String {
        let productName = NoctilucaMeta.productName
        
        if withVersion {
            let productVersion = NoctilucaMeta.version
            return "\(productName)/\(productVersion)"
        } else {
            return productName
        }
    }
}

@MainActor
final class NoctilucaServer: ObservableObject {
    static let shared = NoctilucaServer()

    private let logger = SiriusLogger(category: "NoctilucaServer", subsystem: "app.noctiluca.server")

    let featureProvider = NoctilucaFeatureProvider()

    let authPluginRegistry = AuthPluginRegistry.shared
    let pluginBundleRegistry = PluginBundleRegistry.shared

    private(set) public var identity: (any QUICServerIdentity)?

    let authenticator: Authenticator

    lazy var context: NoctilucaServerContext = {
        NoctilucaServerContext(server: self)
    }()

    var settings: AppSettings {
        get { SettingsStore.shared.settings }
        set { SettingsStore.shared.settings = newValue }
    }

    @Published
    var clients: [UUID: NoctilucaClientSession] = [:]

    @Published
    var state: NoctilucaServerState = .idle

    private var cancellables: Set<AnyCancellable> = []
    private var previousAllowedEntries: [AuthEntry] = []

    init() {
        self.authenticator = Authenticator(registry: authPluginRegistry)

        logger.info("NoctilucaServer initialized")

        Task {
            // FIXME
            try await initialize()
        }
    }
    
    fileprivate func setPreviousAllowedEntries(_ entries: [AuthEntry]) {
        self.previousAllowedEntries = entries
    }
    
    private func loadIdentity() async throws {
        if self.settings.quicTransport.tlsUseAutoconf {
            if self.settings.quicTransport.identity == nil {
                try self.settings.quicTransport.autoconfigureIdentity()
                try self.settings.save()
            }
            
            do {
                try await loadIdentityInternal()
            } catch NoctilucaServerError.identityValidationFailed {
                // 아이덴티티 제거 후 재생성 시도
                self.settings.quicTransport.identity = nil
                try self.settings.save()
                try await loadIdentity()
            }

        } else {
            try await loadIdentityInternal()
        }
    }
    
    private func loadIdentityInternal() async throws {
        let identityManager = ServerIdentityManager.shared
        
        guard let identitySource = self.settings.quicTransport.identity else {
            // throw error: No identity configured
            throw NoctilucaServerError.noIdentityConfigured
        }
        
        let identity = try await identityManager.load(source: identitySource)
        
        guard try await identity.sanityCheck(strict: self.settings.quicTransport.tlsStrictValidation) else {
            self.logger.error("Identity validation failed for identity: \(identity)")
            throw NoctilucaServerError.identityValidationFailed
        }
        
        self.identity = identity
    }
    
    
    func initialize() async throws {
        DisplayLayoutManager.shared.startMonitoring()
        DisplayLayoutManager.shared.updateDisplayLayouts()

        let settings = SettingsStore.shared.settings!
        NoctilucaLoggingConfigurator.apply(settings: settings.logging)

        // 보안 정책 주입
        await pluginBundleRegistry.configure(
            policy: settings.security.pluginBundleSecurityPolicy,
            allowNonisolatedThirdPartyPluginBundle: settings.security.allowNonisolatedThirdPartyPluginBundle
        )

        // 1. 내장 번들 등록
        try await pluginBundleRegistry.registerBuiltinBundles()

        // 2. 외부 번들 스캔/로드 (disallowAll이 아닌 경우)
        if settings.security.pluginBundleSecurityPolicy != .disallowAll {
            await pluginBundleRegistry.loadExternalBundles()
        }

        // T7 검증용 multi-instance smoke (NOC_PLUGIN_HOST_SMOKE=1 일 때만 동작)
        await XPCMultiInstanceSmoke.runIfEnabled()

        // 3. 인증 엔트리 설정 (외부 auth 플러그인 포함)
        await authenticator.setupAllowedEntires(settings.security.allowedEntries)
        self.previousAllowedEntries = settings.security.allowedEntries

        // 4. 인증 수단 변경 감지 구독
        subscribeToAuthEntryChanges()

        ScreenCaptureKitWorkaroundDummyWindow.windowManager.startup()

        // fsaccess feature: settings.fileAccess.enabled 일 때만 host app 안에서
        // 직접 nanonfs NFSv4 listener 를 띄우고 ~/NoctilucaFS 를 NFS 로 마운트.
        await NocFSAccessHost.shared.startupIfEnabled(
            enabled: settings.fileAccess.enabled,
            mountPointPath: settings.fileAccess.mountPointPath,
            useFakeLocks: settings.fileAccess.useFakeLocks,
            writeBackCacheEnabled: settings.fileAccess.writeBackCacheEnabled
        )
    }

    private func subscribeToAuthEntryChanges() {
        SettingsStore.shared.$settings
            .compactMap { $0 }
            .map(\.security.allowedEntries)
            .removeDuplicates()
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newEntries in
                guard let self else { return }
                
                Task {
                    let oldEntries = self.previousAllowedEntries
                    self.setPreviousAllowedEntries(newEntries)
                    
                    Task {
                        await self.authenticator.updateAllowedEntries(from: oldEntries, to: newEntries)
                    }
                }
            }
            .store(in: &cancellables)
    }
    
    func startup() async throws {
        guard case .idle = state else {
            return
        }
                
        do {
#if !DEBUG
            // TODO: 레이스 반드시 일어남
            let licenseState = await LicenseManager.shared.validationState
            guard licenseState != .unlicensed && licenseState != .expired else {
                // TODO: 앱 구매 다이얼로그 등 띄우기
                throw NoctilucaServerError.invalidLicense
            }
#endif
            
            self.state = .preparing
            
            logger.info("Starting up NoctilucaServer...")
            
            try await self.loadIdentity()
            guard let identity = self.identity else {
                throw NoctilucaServerError.noIdentityConfigured
            }
            
            let implementation = settings.transport.implementation
            
            let result = try SiriusServerBuilder()
                .useFeatureProvider(featureProvider)
                .useTransportProtocol(.quic(implementation: implementation, port: settings.quicTransport.listenPort, identity: identity))
                .withExtraConfiguration("someValue", forKey: "someKey")
                .build()
            
            if case .failure(let error) = result {
                logger.error("Failed to build SiriusServer: \(error)")
                throw error
            }
            
            let server = try result.get()
            await server.setDelegate(self)
            
            try await server.setup()
            try await server.startup()
        } catch let error as QUICServerIdentityLoadError {
            self.state = .idle
            await self.handleError(identityLoadError: error)
        } catch {
            logger.error("Failed to start NoctilucaServer: \(error)")
            AppNotification.serverStartFailed(error: error).postIfEnabled()
            self.state = .idle
            throw error
        }
    }
    
    func shutdown() async throws {
        // fsaccess feature 가 켜져 있었다면 unmount + listener stop 을 먼저.
        await NocFSAccessHost.shared.shutdownAndUnmount()

        guard case .running(let server) = state else {
            return
        }

        logger.info("Shutting down NoctilucaServer...")

        try await server.shutdown()

        // SiriusServer.shutdown 이 ClientSession 들을 닫으면서 ProjectionChannel.destroy 까지
        // 흘러간 뒤, AX/Workspace 자원을 최종 정리한다. 서버 stop → 재시작 사이에
        // stale AppSession / workspace observer 가 남지 않도록 한다.
        await DesktopContextManager.shared.shutdown()
    }
}

fileprivate extension NoctilucaServer {
    func addClientSession(_ session: NoctilucaClientSession) async {
        await self.clients[session.id] = session
    }
    
    func removeClientSession(_ session: NoctilucaClientSession) async {
        let id = await session.id
        
        self.clients[id] = nil
        self.clients.removeValue(forKey: id)
    }
    
    func mutateState(to newState: NoctilucaServerState) {
        self.state = newState
    }
}


extension NoctilucaServer: SiriusServerDelegate {
    nonisolated func siriusServerDidStart(_ server: SiriusKit.SiriusServer) {
        logger.info("NoctilucaServer is now running.")
        Task {
            await AppNotification.serverStarted.post()
            await self.mutateState(to: .running(server: server))
        }
    }
    
    nonisolated func siriusServerDidStop(_ server: SiriusKit.SiriusServer) {
        logger.info("NoctilucaServer has stopped.")
        Task { @MainActor in
            AppNotification.serverStopped.post()
            self.mutateState(to: .idle)
        }
    }
    
    nonisolated func siriusServer(_ server: SiriusKit.SiriusServer, didEncounterError error: any Error) {
        logger.error("NoctilucaServer encountered an error: \(error)")
    }
    
    nonisolated func siriusServerDidAcceptClientSession(_ server: SiriusKit.SiriusServer, session: SiriusKit.ClientSession) async {
        // NoctilucaClientSession.init 내부에서 ClientSession.delegate가 동기적으로 세팅된다.
        // SiriusServer.createClientSession은 이 delegate 메서드가 await 귀환한 뒤에 session.activate()를
        // 호출하므로, 여기서 MainActor 경계로 진입해 NoctilucaClientSession 생성을 끝내야 한다.
        // 그렇지 않으면 loopback 환경에서 activate() 내부 Task가 쏘는
        // clientSessionDidCreateMainChannel 콜백이 delegate가 아직 nil인 상태에서 실행되어 소실되고,
        // 메인 채널 이벤트 루프가 시작되지 않아 5초 뒤 phase shift assertion이 터진다.
        await MainActor.run {
            let clientSession = NoctilucaClientSession(session: session, server: self.context)

            // 나머지 초기화/수용 체크는 delegate 리턴을 블로킹할 이유가 없으므로 백그라운드 Task로 분리한다.
            // clientSession은 이 Task가 strong-capture하므로, ClientSession.delegate(weak)에서
            // 해제되는 문제는 없다.
            Task { @MainActor in
                await clientSession.setDelegate(self)
                await clientSession.initialize()

                let maxConcurrentSessions = self.settings.general.maxConcurrentSessions

                guard self.clients.count < maxConcurrentSessions else {
                    self.logger.info("Maximum concurrent sessions exceeded (\(maxConcurrentSessions)), rejecting session")
                    Task {
                        await clientSession.closeFatally(
                            notice: .sessionAllocationFailed,
                            closure: .internalServerError
                        )
                    }
                    return
                }

                await self.addClientSession(clientSession)
            }
        }
    }
    
    nonisolated func siriusServerDidFailToAcceptClientSession(_ server: SiriusKit.SiriusServer, error: any Error) {
    }
}

extension NoctilucaServer: NoctilucaClientSessionDelegate {
    nonisolated func noctilucaClientSessionDidClose(_ session: NoctilucaClientSession) {
        Task {
            await self.removeClientSession(session)
        }
    }
}
