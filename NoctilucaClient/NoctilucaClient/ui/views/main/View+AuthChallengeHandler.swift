//
//  AuthChallengeHandlerView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/11/25.
//

import SwiftUI
import Combine

import SiriusKitClient

extension View {
    @ViewBuilder
    func setupAuthChallengeHandler(client: NoctilucaClient?) -> some View {
        if let client = client {
            self.modifier(AuthChallengeHandlerModifier(client: client))
        } else {
            self
        }
    }
}

@MainActor
struct AuthChallengeHandlerModifier: ViewModifier {
    let client: NoctilucaClient
    
    @State
    var authChallenge: AuthChallenge? = nil
    
    @State
    var shouldPresentAuthChallengeSheet: Bool = false
    
    func body(content: Content) -> some View {
        content
            // HACK: 레이스 컨디션 일어나서 sheet이 표시되어도 내용이 비어있는 경우가 발생함
            .if(authChallenge != nil) {
                $0
                    .sheet(isPresented: $shouldPresentAuthChallengeSheet) {
                        if let authChallenge = self.authChallenge {
                            AuthChallengeSheetView(authChallenge: authChallenge) { action in
                                Task {
                                    await handleAuthChallengeResponse(action)
                                }
                            }
                        }
                    }
            }
            .onReceive(client.uiEvents) { event in
                guard case .receivedAuthChallenge(let challenge) = event else {
                    return
                }
                
                handleAuthChallenge(challenge)
            }
    }
    
    func handleAuthChallenge(_ challenge: AuthChallenge) {
        self.authChallenge = challenge
        self.shouldPresentAuthChallengeSheet = true
    }
    
    func handleAuthChallengeResponse(_ action: AuthChallengeSheetAction) async {
        self.shouldPresentAuthChallengeSheet = false
        
        switch action {
        case .cancel:
            await client.close()
            return
        case .confirm(let method, let nonce, let payload):
            try? await client.sendAuthRequest(method, nonce: nonce, payload: payload)
        }
    }
}
