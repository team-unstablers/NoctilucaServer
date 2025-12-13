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
    func setupClientErrorHandler(client: NoctilucaClient?, handler: @escaping (NoctilucaClientError) -> Void) -> some View {
        if let client = client {
            self.modifier(ClientErrorHandlerModifier(client: client, handler: handler))
        } else {
            self
        }
    }
}

@MainActor
struct ClientErrorHandlerModifier: ViewModifier {
    let client: NoctilucaClient
    let handler: (NoctilucaClientError) -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(client.uiEvents) { event in
                guard case .errorOccurred(let error) = event else {
                    return
                }
                
                handler(error)
            }
    }
}
