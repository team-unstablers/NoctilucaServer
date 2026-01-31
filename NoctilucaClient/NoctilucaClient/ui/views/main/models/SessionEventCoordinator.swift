//
//  SessionEventCoordinator.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/28/26.
//
import Foundation
import Combine

import SiriusKitClient

class SessionEventCoordinator: ObservableObject {
    private let logger = NoctilucaLogger(category: "SessionEventCoordinator")
    private var eventSubscription: AnyCancellable? = nil

    private let mainWindowViewModel: MainWindowViewModel
    private weak var client: NoctilucaClient?

    @Published
    var phase: NoctilucaClientPhase = .initial

    @Published
    var authChallenge: AuthChallenge? = nil

    @Published
    var shouldPresentAuthChallengeSheet: Bool = false

    @Published
    var pingRTT: TimeInterval? = nil

    var availableAuthMethods: [ClientAuthMethod] {
        guard let client, let authChallenge else {
            return []
        }
        return client.authenticator.availableMethods(for: authChallenge)
    }

    init(_ mainWindowViewModel: MainWindowViewModel) {
        self.mainWindowViewModel = mainWindowViewModel
    }

    func bind(to client: NoctilucaClient) {
        self.unbind()

        self.client = client
        self.eventSubscription = client.uiEvents
            .receive(on: RunLoop.main)
            .sink { [weak self] event in
                self?.handleEvent(event)
            }

        // manually update current phase
        self.phase = client.phase
    }

    func unbind() {
        self.eventSubscription?.cancel()
        self.eventSubscription = nil

        self.client = nil
        self.phase = .initial
        self.authChallenge = nil
        self.shouldPresentAuthChallengeSheet = false
        self.pingRTT = nil
    }

    private func handleEvent(_ event: NoctilucaClientUIEvent) {
        switch event {
        case .phaseChanged(let phase):
            self.phase = phase
            self.mainWindowViewModel.handleClientPhaseChanged(phase)

        case .receivedAuthChallenge(let authChallenge):
            self.authChallenge = authChallenge
            self.shouldPresentAuthChallengeSheet = true

        case .receivedAuthResponse(let authResponse):
            self.logger.info("Received auth response: \(authResponse.sessionID?.uuidString ?? "(nil)")")
            self.authChallenge = nil
            self.shouldPresentAuthChallengeSheet = false

        case .pingRTTUpdated(let rtt):
            self.pingRTT = rtt
            self.mainWindowViewModel.averagePingRTT = rtt

        case .inputWarningUpdated(let warning):
            self.mainWindowViewModel.handleInputWarningUpdated(warning)

        case .errorOccurred(let error):
            self.logger.error("Client error occurred: \(error.localizedDescription)")
            self.mainWindowViewModel.handleClientError(error)

        case .FIXME_projectionStarted(let projectionSession):
            self.mainWindowViewModel.displayLayer = projectionSession.displayLayer
            
        case .receivedGoodbye(let code, let reason):
            // TODO
            break
            
        default:
            break
        }
    }

    func handleAuthChallengeResponse(_ action: AuthChallengeSheetAction) async {
        guard let client, let authChallenge else {
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
}
