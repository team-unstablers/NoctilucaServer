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
    func setupClientPhaseHandler(client: NoctilucaClient?, action: @escaping (NoctilucaClientPhase) -> Void) -> some View {
        if let client = client {
            self.modifier(ClientPhaseHandlerModifier(client: client, action: action))
        } else {
            self
        }
    }
}

@MainActor
struct ClientPhaseHandlerModifier: ViewModifier {
    let client: NoctilucaClient
    let action: (NoctilucaClientPhase) -> Void
   
    func body(content: Content) -> some View {
        content
            .onReceive(client.uiEvents) { event in
                guard case .phaseChanged(let phase) = event else {
                    return
                }
                
                action(phase)
            }
    }
}
