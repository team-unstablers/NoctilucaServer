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
    
    @Published
    var phase: NoctilucaClientPhase = .initial
    
    @Published
    var authChallenge: AuthChallenge? = nil
    
    @Published
    var pingRTT: TimeInterval? = nil
    
    init(_ mainWindowViewModel: MainWindowViewModel) {
        self.mainWindowViewModel = mainWindowViewModel
    }
    
    func bind(to client: NoctilucaClient) {
        self.unbind()
        
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
        
        self.phase = .initial
        self.authChallenge = nil
        self.pingRTT = nil
    }
    
    private func handleEvent(_ event: NoctilucaClientUIEvent) {
        switch event {
        case .phaseChanged(let phase):
            self.phase = phase
            self.mainWindowViewModel.handleClientPhaseChanged(phase)
            
        case .receivedAuthChallenge(let authChallenge):
            self.authChallenge = authChallenge
            
        case .receivedAuthResponse(let authResponse):
            self.logger.info("Received auth response: \(authResponse.sessionID?.uuidString ?? "(nil)")")
            self.authChallenge = nil
            
        case .pingRTTUpdated(let rtt):
            self.pingRTT = rtt
        case .errorOccurred(let error):
            self.logger.error("Client error occurred: \(error.localizedDescription)")
        
        default:
            break
        }
    }
    
}
