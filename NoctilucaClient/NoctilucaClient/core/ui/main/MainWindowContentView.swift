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
    var viewModel: SessionWindowViewModel

    var body: some View {
        content
            .if(viewModel.remoteSession != nil) {
                if let remoteSession = viewModel.remoteSession,
                   let authChallenge = remoteSession.authChallenge {
                    // FIXME: 추후 고쳐야 함
                    $0.dialog(isPresented: .init(get: { remoteSession.shouldPresentAuthChallengeSheet }, set: { remoteSession.shouldPresentAuthChallengeSheet = $0 })) {
                        AuthChallengeSheetView(
                            authChallenge: authChallenge,
                            availableMethods: remoteSession.availableAuthMethods.filter { $0 != .sshKey }
                        ) { action in
                            Task { @MainActor in
                                await viewModel.handleAuthChallengeResponse(action)
                            }
                        }
                        .id(authChallenge.nonce)
                    }
                } else {
                    $0
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
            if let remoteSession = viewModel.remoteSession,
               let projection = remoteSession.projection
            {
                let displayLayoutManager = remoteSession.client.projectionChannel.displayLayoutManager
                // TODO: -1 쓰지 마세요1!!
                let primaryDisplayID = displayLayoutManager.primaryDisplayID ?? -1
                
                RemoteSessionProjectionView(
                    remoteSession: remoteSession,
                    projection: projection,
                    source: .displayID(primaryDisplayID)
                )
                    .environmentObject(remoteSession)
            }
        default:
            EmptyView()
        }
    }
}
