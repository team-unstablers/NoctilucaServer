//
//  RemoteSession.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/28/26.
//
import Foundation
import Combine
import Security

import SiriusKitClient

@MainActor
class RemoteSession: ObservableObject {
    private let logger = NoctilucaLogger(category: "RemoteSession")
    private var eventSubscription: AnyCancellable? = nil
    
    var parent: Weak<SessionWindowViewModel>?

    private(set) var client: NoctilucaClient

    @Published
    private(set) var phase: NoctilucaClientPhase = .initial

    @Published
    private(set) var authChallenge: AuthChallenge? = nil

    @Published
    var shouldPresentAuthChallengeSheet: Bool = false

    @Published
    var shouldPresentIdentityValidationSheet: Bool = false

    @Published
    private(set) var pendingServerIdentity: ServerIdentity? = nil

    @Published
    private(set) var identityValidationExtraInfo: ServerIdentityValidationSheetViewExtraInfo = .none

    @Published
    private(set) var pingRTT: TimeInterval? = nil
    
    @Published
    private(set) var projection: Projection? = nil
    
    @Published
    private(set) var hidio: HIDIO? = nil
    
    private let errorEvents = PassthroughSubject<NoctilucaClientError, Never>()

    var errorPublisher: AnyPublisher<NoctilucaClientError, Never> {
        errorEvents.eraseToAnyPublisher()
    }

    var availableAuthMethods: [ClientAuthMethod] {
        guard let authChallenge else {
            return []
        }
        
        return client.authenticator.availableMethods(for: authChallenge)
    }

    init(_ client: NoctilucaClient) {
        self.client = client
        
        self.subscribeClientEvents()
    }
    
    @MainActor
    deinit {
        self.unsubscribeClientEvents()

        let client = self.client
        Task.detached {
            await client.close()
        }
    }
    
    func setup() async throws {
        try await self.client.setup()
    }
    
    func startup() async throws {
        try await self.client.startup()
    }
    
    func shutdown() async {
        await self.client.close()
    }

    private func subscribeClientEvents() {
        self.eventSubscription = client.uiEvents
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                Task { @MainActor in
                    self?.handleEvent(event)
                }
            }

        // manually update current phase
        self.phase = client.phase
    }

    private func unsubscribeClientEvents() {
        self.eventSubscription?.cancel()
        self.eventSubscription = nil
    }

    private func handleEvent(_ event: NoctilucaClientUIEvent) {
        switch event {
        case .phaseChanged(let phase):
            self.phase = phase
            // self.mainWindowViewModel.handleClientPhaseChanged(phase)

        case .receivedAuthChallenge(let authChallenge):
            self.authChallenge = authChallenge
            self.shouldPresentAuthChallengeSheet = true

        case .receivedAuthResponse(let authResponse):
            self.logger.info("Received auth response: \(authResponse.sessionID?.uuidString ?? "(nil)")")
            self.authChallenge = nil
            self.shouldPresentAuthChallengeSheet = false

        case .pingRTTUpdated(let rtt):
            self.pingRTT = rtt
            break
            
        /*
        case .inputWarningUpdated(let warning):
            self.mainWindowViewModel.handleInputWarningUpdated(warning)
         */

        case .errorOccurred(let error):
            self.logger.error("Client error occurred: \(error.localizedDescription)")
            // 재전송
            self.errorEvents.send(error)
            
        case .channelCreated(let feature, let channel):
            self.handleChannelOpen(channel: channel, for: feature)
        case .channelClosed(let channelID):
            self.handleChannelClose(channelID)
            
        case .receivedGoodbye(let code, let reason):
            // TODO
            break

        case .serverIdentityValidationNeeded(let identity):
            Task {
                do {
                    try await self.handleIdentityValidationRequest(identity: identity)
                } catch {
                    // TODO: 에러 처리
                    logger.error("Failed to handle identity validation request: \(error.localizedDescription)")
                }
            }
        }
    }

    func handleIdentityValidationRequest(identity: ServerIdentity) async throws {
        guard let parent = self.parent?.ref else {
            return
        }
        
        let endpointURL = parent.endpointURL
        var extraInfo: ServerIdentityValidationSheetViewExtraInfo = .none
        
        if let knownHost = try await KeychainBackedKnownHostStore.shared.getKnownHost(endpoint: endpointURL) {
            let fingerprint = try identity.fingerprint()
            
            if knownHost.fingerprint == fingerprint {
                // 이미 신뢰된 호스트임
                logger.info("Server identity matches known host. Automatically trusting.")
                try await parent.performReconnect(decision: SucceedValidationDecision(fingerprint: fingerprint, decision: .allow))
                
                return
            } else {
                // 지문 불일치 일어남, 사용자에게 경고해야 함.
                extraInfo = .fingerprintMismatch(
                    expectedFingerprint: knownHost.fingerprint.asFingerprintString(),
                    actualFingerprint: fingerprint.asFingerprintString()
                )
                
                // UI 프레젠테이션으로 넘어간다
            }
        }
        
        self.pendingServerIdentity = identity
        self.identityValidationExtraInfo = extraInfo
        self.shouldPresentIdentityValidationSheet = true
    }

    func handleAuthChallengeResponse(_ action: AuthChallengeSheetAction) async {
        guard let authChallenge else {
            return
        }

        self.shouldPresentAuthChallengeSheet = false

        switch action {
        case .cancel:
            await client.close()
            return
        case .confirm(let entry):
            guard let payload = client.authenticator.payload(for: entry, nonce: authChallenge.nonce) else {
                client.logger.error("Failed to build auth payload for method: \(entry.method.rawValue)")
                return
            }
            try? await client.sendAuthRequest(entry.method.rawValue, nonce: authChallenge.nonce, payload: payload)
        }
    }
    
    private func handleChannelOpen(channel: Channel, for feature: SiriusFeature) {
        switch feature {
        case .projection:
            guard let projectionChannel = channel as? ProjectionChannel else {
                return
            }

            self.projection = Projection(self, channel: projectionChannel)
            Task.detached { [weak self] in
                try? await self?.projection?.startAudioProjection()
            }
            
        case .hidio:
            guard let hidioChannel = channel as? HIDIOChannel else {
                return
            }
            
            self.hidio = HIDIO(self, channel: hidioChannel)
        default:
            break
        }
    }
    
    private func handleChannelClose(_ channelID: UUID) {
        if channelID == projection?.channelID {
            self.projection = nil
        }
        
        if channelID == hidio?.channelID {
            self.hidio = nil
        }
    }
}
