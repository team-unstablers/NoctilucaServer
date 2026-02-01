//
//  MainWindowContentView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import SwiftUI

import SiriusKitClient

fileprivate struct MainWindowContentViewInternal: View {
    @EnvironmentObject
    var viewModel: SessionWindowViewModel

    @StateObject
    var remoteSession: RemoteSession
    
    var body: some View {
        switch viewModel.phase {
        case .connecting:
            MainWindowConnectingPhaseContentView()
                .if(remoteSession.shouldPresentAuthChallengeSheet) {
                    if let authChallenge = remoteSession.authChallenge {
                        // AuthChallenge 바인딩
                        let isPresentedBinding = Binding(
                            get: { remoteSession.shouldPresentAuthChallengeSheet },
                            set: { remoteSession.shouldPresentAuthChallengeSheet = $0 }
                        )
                        
                        $0.dialog(isPresented: isPresentedBinding) {
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
                    }
                }
        case .connected:
            if let remoteSession = viewModel.remoteSession {
                if let projection = remoteSession.projection {
                    if let primaryDisplayID = remoteSession.client.projectionChannel.displayLayoutManager.primaryDisplayID {
                        RemoteSessionProjectionView(
                            remoteSession: remoteSession,
                            projection: projection,
                            source: .displayID(primaryDisplayID)
                        )
                        .environmentObject(remoteSession)
                    } else {
                        ProgressView("Waiting for display configuration...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .task {
                                // 혹시 정보가 누락되었을 경우를 대비해 재요청
                                try? await remoteSession.client.projectionChannel.updateDisplayLayout()
                            }
                    }
                } else {
                    ProgressView("Initializing projection...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ProgressView("Preparing session...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        default:
            EmptyView()
        }
    }
}

struct MainWindowContentView: View {
#if os(iOS)
    @Environment(\.horizontalSizeClass)
    var horizontalSizeClass
#endif
    
    @EnvironmentObject
    var viewModel: SessionWindowViewModel
    
    
    var body: some View {
        content
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
        case .connecting, .connected:
            if let remoteSession = viewModel.remoteSession {
                MainWindowContentViewInternal(remoteSession: remoteSession)
            }
        }
    }
}
