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
#if os(macOS)
                $0
                    .sheet(isPresented: $shouldPresentAuthChallengeSheet) {
                        if let authChallenge = self.authChallenge {
                            AuthChallengeSheetView(
                                authChallenge: authChallenge,
                                availableMethods: client.authenticator.availableMethods(for: authChallenge)
                            ) { action in
                                Task {
                                    await handleAuthChallengeResponse(action, challenge: authChallenge)
                                }
                            }
                            .id(authChallenge.nonce)
                        }
                    }
#elseif os(iOS)
                $0
                    .fullScreenCover(isPresented: $shouldPresentAuthChallengeSheet) {
                        ZStack {
                            Color.black.opacity(0.4)
                                .ignoresSafeArea()
                            
                            if let authChallenge = self.authChallenge {
                                AuthChallengeSheetView(
                                    authChallenge: authChallenge,
                                    availableMethods: client.authenticator.availableMethods(for: authChallenge)
                                ) { action in
                                    Task {
                                        await handleAuthChallengeResponse(action, challenge: authChallenge)
                                    }
                                }
                                .id(authChallenge.nonce)
                                .background(.background)
                                .cornerRadius(12)
                                .padding(12)
                            }
                        }
                        .presentationBackground(.clear)
                    }
#endif
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
    
    func handleAuthChallengeResponse(_ action: AuthChallengeSheetAction, challenge: AuthChallenge) async {
        self.shouldPresentAuthChallengeSheet = false
        
        switch action {
        case .cancel:
            await client.close()
            return
        case .confirm(let entry):
            guard let payload = client.authenticator.payload(for: entry) else {
                client.logger.error("Failed to build auth payload for method: \(entry.method.rawValue)")
                return
            }
            try? await client.sendAuthRequest(entry.method.rawValue, nonce: challenge.nonce, payload: payload)
        }
    }
}
