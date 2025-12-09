//
//  NOCSiriusServerApplication.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import Foundation
import Combine

import SiriusKit

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
    
    private static let defaultKeychainIdentity = "pl.unstabler.noctiluca.server.testIdentity"
    
    private let logger = SiriusLogger(category: "NoctilucaServer", subsystem: "pl.unstabler.noctiluca.NoctilucaServer")
    
    let featureProvider = NoctilucaFeatureProvider()
    
    let authPluginRegistry = AuthPluginRegistry.shared
    let pluginBundleRegistry = PluginBundleRegistry.shared
    
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
    
    private func __FIXME__ensureKeychainIdentity(identityLabel: String) throws {
        if (try KeychainQUICServerIdentity.checkIdentityExistance(label: identityLabel)) {
            return
        }
        
        logger.info("Creating self-signed identity with label: \(identityLabel)...")
        
        let args = QUICServerIdentityCreationArgs(
            identityLabel: identityLabel,
            commonName: identityLabel,
            organizationName: "team unstablers Inc.",
            organizationalUnitName: "test unit",
            countryName: "KR",
            validityPeriodInDays: 365
        )
        
        _ = try KeychainQUICServerIdentity.createSelfSignedIdentity(args: args)
    }
    
    func initialize() async throws {
        self.settings = try AppSettings.load()
        
        try await pluginBundleRegistry.registerBuiltinBundles()
    }
    
    func startup() async throws {
        guard case .idle = state else {
            return
        }
        
        do {
            self.state = .preparing
            
            logger.info("Starting up NoctilucaServer...")
            try __FIXME__ensureKeychainIdentity(identityLabel: Self.defaultKeychainIdentity)
            
            
            let result = try SiriusServerBuilder()
                .useFeatureProvider(featureProvider)
                .useTransportProtocol(.quic(port: settings.quicTransport.listenPort, identitySource: .keychain(label: Self.defaultKeychainIdentity)))
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
        self.state = .running(server: server)
    }
    
    func siriusServerDidStop(_ server: SiriusKit.SiriusServer) {
        logger.info("NoctilucaServer has stopped.")
        self.state = .idle
    }
    
    func siriusServer(_ server: SiriusKit.SiriusServer, didEncounterError error: any Error) {
        logger.error("NoctilucaServer encountered an error: \(error)")
    }
    
    func siriusServerDidAcceptClientSession(_ server: SiriusKit.SiriusServer, session: SiriusKit.ClientSession) {
        let session = NoctilucaClientSession(session: session, server: context)
        session.initialize()
        
        self.clients[session.id] = session
    }
    
    func siriusServerDidFailToAcceptClientSession(_ server: SiriusKit.SiriusServer, error: any Error) {
    }
}
