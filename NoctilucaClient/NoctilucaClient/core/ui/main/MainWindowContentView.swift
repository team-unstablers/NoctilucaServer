//
//  MainWindowContentView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import SwiftUI

import SiriusKitClient

fileprivate struct MainWindowContentViewInternal: View {
    @Environment(SessionWindowViewModel.self)
    var viewModel: SessionWindowViewModel

    let remoteSession: RemoteSession
    
    var body: some View {
        switch viewModel.phase {
        case .connecting:
            MainWindowConnectingPhaseContentView()
                .dialog(isPresented: Binding(
                    get: { remoteSession.shouldPresentAuthChallengeSheet },
                    set: { remoteSession.shouldPresentAuthChallengeSheet = $0 }
                )) {
                    if let authChallenge = remoteSession.authChallenge {
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
                .detachedSheet(isPresented: Binding(
                    get: { remoteSession.shouldPresentIdentityValidationSheet },
                    set: { remoteSession.shouldPresentIdentityValidationSheet = $0 }
                )) {
                    if let identity = remoteSession.pendingServerIdentity,
                       case .sslCertificate(let leaf, let chain) = identity {
                        ServerIdentityValidationSheetView(
                            hostname: viewModel.endpointURL,
                            leaf: leaf,
                            chain: chain,
                            extraInfo: remoteSession.identityValidationExtraInfo
                        ) { action in
                            Task { @MainActor in
                                if case .proceed(let type) = action {
                                    do {
                                        guard let fingerprint = leaf.extractFingerprint() else {
                                            print("서버 인증서에서 지문을 추출하지 못했습니다.")
                                            return
                                        }

                                        if type == .always {
                                            let entry = KnownHostEntry(
                                                endpoint: viewModel.endpointURL,
                                                fingerprint: fingerprint
                                            )
                                            try await KeychainBackedKnownHostStore.shared.saveKnownHost(entry)
                                        }

                                        try await viewModel.performReconnect(decision: SucceedValidationDecision(
                                            fingerprint: fingerprint, decision: .allow
                                        ))
                                    } catch {
                                        viewModel.presentConnectionError(error)
                                    }
                                } else {
                                    await viewModel.stopSession(force: true)
                                }
                            }
                        }
                    }
                }
        case .connected:
            if let remoteSession = viewModel.remoteSession {
                if let projection = remoteSession.projection,
                   let hidio = remoteSession.hidio
                {
                    MainWindowRemoteSessionView(remoteSession: remoteSession, projection: projection, hidio: hidio)
                } else {
                    ProgressView(String(localized: "mainwindow.content.initializing-projection-channel", defaultValue: "프로젝션 채널 초기화 중..."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ProgressView(String(localized: "mainwindow.content.preparing-session", defaultValue: "세션 준비 중..."))
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
    
    @Environment(SessionWindowViewModel.self)
    var viewModel: SessionWindowViewModel


    var body: some View {
        content
    }
    
    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .newConnection:
            MainWindowNewConnectionPhaseContentView()
        case .connecting, .connected:
            if let remoteSession = viewModel.remoteSession {
                MainWindowContentViewInternal(remoteSession: remoteSession)
            }
        }
    }
}
