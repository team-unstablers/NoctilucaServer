//
//  MainWindowContentView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import SwiftUI

import SiriusKitClient

struct MainWindowContentView: View {
#if os(iOS)
    @Environment(\.horizontalSizeClass)
    var horizontalSizeClass
#endif

    @EnvironmentObject
    var viewModel: MainWindowViewModel

    var body: some View {
        content
            // HACK: 레이스 컨디션 일어나서 sheet이 표시되어도 내용이 비어있는 경우가 발생함
            .if(viewModel.sessionEventCoordinator.authChallenge != nil) {
                $0.dialog(isPresented: $viewModel.sessionEventCoordinator.shouldPresentAuthChallengeSheet) {
                    if let authChallenge = viewModel.sessionEventCoordinator.authChallenge {
                        AuthChallengeSheetView(
                            authChallenge: authChallenge,
                            availableMethods: viewModel.sessionEventCoordinator.availableAuthMethods.filter { $0 != .sshKey }
                        ) { action in
                            Task {
                                await viewModel.sessionEventCoordinator.handleAuthChallengeResponse(action)
                            }
                        }
                        .id(authChallenge.nonce)
                    }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .newConnection:
            MainWindowNewConnectionPhaseContentView()
#if os(iOS)
                .safeAreaPadding(.vertical)
                .padding(.top, horizontalSizeClass == .compact ? 0 : 32)
#endif
        case .connecting:
            MainWindowConnectingPhaseContentView()
        case .connected:
            MainWindowMainPhaseContentView()
        default:
            EmptyView()
        }
    }
}
