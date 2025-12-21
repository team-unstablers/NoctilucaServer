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
    func setupClientStatisticsHandler(client: NoctilucaClient?, viewModel: MainWindowViewModel) -> some View {
        if let client = client {
            self.modifier(ClientStatisticsHandlerModifier(client: client, viewModel: viewModel))
        } else {
            self
        }
    }
}

@MainActor
struct ClientStatisticsHandlerModifier: ViewModifier {
    let client: NoctilucaClient
    
    @ObservedObject
    var viewModel: MainWindowViewModel
   
    func body(content: Content) -> some View {
        content
            .onReceive(client.uiEvents) { event in
                switch event {
                case .pingRTTUpdated(let rtt):
                    print("RTT: \(rtt * 1000) ms")
                    viewModel.averagePingRTT = rtt
                case .inputWarningUpdated(let warning):
                    viewModel.handleInputWarningUpdated(warning)
                default:
                    break
                }
            }
    }
}
