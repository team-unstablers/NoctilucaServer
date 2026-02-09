//
//  NOCSiriusServerApplication.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import Foundation
import Combine

import SiriusKit

enum NoctilucaServerError: LocalizedError {
    case noIdentityConfigured
    case identityValidationFailed
    
    var errorDescription: String? {
        switch self {
        case .noIdentityConfigured:
            return "No identity is configured for the server."
        case .identityValidationFailed:
            return "The configured identity failed validation."
        }
    }
}

enum NoctilucaServerState {
    case idle
    case preparing
    case running(server: SiriusServer)
}

class NoctilucaServerContext: ServerContext {
    private let server: NoctilucaServer
    
    var featureProvider: NoctilucaFeatureProvider { server.featureProvider }
    
    var authenticator: Authenticator { server.authenticator }
    var settings: AppSettings { server.settings }
    
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

// @MainActor <- 근데 과거의 나는 이걸 왜 붙였지? 인생 편하게 살고 싶었나..?
class NoctilucaServer: ObservableObject {
    static let shared = NoctilucaServer()
    
    private let logger = SiriusLogger(category: "NoctilucaServer", subsystem: "app.noctiluca.server")
    
    let featureProvider = NoctilucaFeatureProvider()
    
    let authPluginRegistry = AuthPluginRegistry.shared
    let pluginBundleRegistry = PluginBundleRegistry.shared
    
    private(set) public var identity: TLSIdentity?
    
    let authenticator: Authenticator
    
    var context: NoctilucaServerContext!
    
    @Published
    var settings: AppSettings = AppSettings()

    @Published
    var clients: [UUID: NoctilucaClientSession] = [:]
    
    @Published
    var state: NoctilucaServerState = .idle

    init() {
        self.authenticator = Authenticator(registry: authPluginRegistry)
        self.context = NoctilucaServerContext(server: self)
        // FIXME: 이건 AppDelegate에서 하세요.
        SiriusLogger.configure(minimumLevel: .trace)
        
        logger.info("NoctilucaServer initialized")
        
        Task {
            // FIXME
            try await initialize()
        }
        
        /*
        let bundlePath = "/Users/cheesekun/Library/Developer/Xcode/DerivedData/NoctilucaServer-bmvtwemvjsiisrajoyirlzkenmct/Build/Products/Debug/SamplePluginBundle.nocbundle"
        let bundleURL = URL(fileURLWithPath: bundlePath)
        Task {
            do {
                try await pluginBundleRegistry.loadBundle(from: bundleURL)
            } catch {
                logger.error("Failed to load plugin bundle from \(bundlePath): \(error)")
            }
        }
         */
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
        guard let identity = self.settings.quicTransport.identity else {
            // throw error: No identity configured
            throw NoctilucaServerError.noIdentityConfigured
        }
        
        let quicIdentity = identity.load()
        
        guard try await quicIdentity.sanityCheck(strict: self.settings.quicTransport.tlsStrictValidation) else {
            self.logger.error("Identity validation failed for identity: \(identity)")
            throw NoctilucaServerError.identityValidationFailed
        }
        
        self.identity = identity
    }
    
    
    @MainActor
    func initialize() async throws {
        DisplayLayoutManager.shared.startMonitoring()
        DisplayLayoutManager.shared.updateDisplayLayouts()
        
        self.settings = try AppSettings.load()
        
        try await pluginBundleRegistry.registerBuiltinBundles()
        await authenticator.setupAllowedEntires(self.settings.security.allowedEntries)
        
        ScreenCaptureKitWorkaroundDummyWindow.windowManager.startup()
        
        if settings.general.autoStart {
            Task {
                try await startup()
            }
        }
    }
    
    @MainActor
    func startup() async throws {
        guard case .idle = state else {
            return
        }
        
        do {
            self.state = .preparing
            
            logger.info("Starting up NoctilucaServer...")
            
            try await self.loadIdentity()
            guard let identity = self.identity else {
                throw NoctilucaServerError.noIdentityConfigured
            }
            
            let implementation = settings.transport.implementation
            
            let result = try SiriusServerBuilder()
                .useFeatureProvider(featureProvider)
                .useTransportProtocol(.quic(implementation: implementation, port: settings.quicTransport.listenPort, identitySource: identity.identitySource))
                .withExtraConfiguration("someValue", forKey: "someKey")
                .build()
            
            if case .failure(let error) = result {
                logger.error("Failed to build SiriusServer: \(error)")
                throw error
            }
            
            let server = try result.get()
            server.delegate = self
            
            try await server.setup()
            try await server.startup()
        } catch {
            logger.error("Failed to start NoctilucaServer: \(error)")
            AppNotification.serverStartFailed(error: error).post()
            self.state = .idle
            throw error
        }
    }
    
    func shutdown() async throws {
        guard case .running(let server) = state else {
            return
        }
        
        logger.info("Shutting down NoctilucaServer...")
        
        try await server.shutdown()
    }
}


extension NoctilucaServer: SiriusServerDelegate {
    func siriusServerDidStart(_ server: SiriusKit.SiriusServer) {
        logger.info("NoctilucaServer is now running.")
        Task {
            await MainActor.run {
                AppNotification.serverStarted.post()
                self.state = .running(server: server)
            }
        }
    }
    
    func siriusServerDidStop(_ server: SiriusKit.SiriusServer) {
        logger.info("NoctilucaServer has stopped.")
        Task { @MainActor in
            AppNotification.serverStopped.post()
            self.state = .idle
        }
    }
    
    func siriusServer(_ server: SiriusKit.SiriusServer, didEncounterError error: any Error) {
        logger.error("NoctilucaServer encountered an error: \(error)")
    }
    
    func siriusServerDidAcceptClientSession(_ server: SiriusKit.SiriusServer, session: SiriusKit.ClientSession) {
        let session = NoctilucaClientSession(session: session, server: context)
        session.delegate = self
        session.initialize()
        
        Task { @MainActor in
            self.clients[session.id] = session
        }
    }
    
    func siriusServerDidFailToAcceptClientSession(_ server: SiriusKit.SiriusServer, error: any Error) {
    }
}

extension NoctilucaServer: NoctilucaClientSessionDelegate {
    func noctilucaClientSessionDidClose(_ session: NoctilucaClientSession) {
        Task { @MainActor in
            self.clients[session.id] = nil
        }
    }
}
