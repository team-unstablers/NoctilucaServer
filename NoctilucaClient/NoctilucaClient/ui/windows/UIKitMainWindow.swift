//
//  MainWindow.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

#if os(iOS)
import Foundation

import SwiftUI
import Combine

import SiriusKitClient

enum MainWindowToolbarStyle {
    case standard
    case compact
}

struct UIKitMainWindow: View {
    @EnvironmentObject
    var viewModel: MainWindowViewModel

    @EnvironmentObject
    private var settingsStore: SettingsStore

    private var sessionSettingsActions: [SessionSettingsSheet.Action] {
        switch viewModel.sessionSettingsSheetMode {
        case .quickConnect:
            let canConnect = viewModel.canConnectFromDraft
            return [
                .init(kind: .cancel, title: "취소", role: .cancel) {
                    viewModel.dismissSessionSettingsSheet()
                },
                .init(kind: .secondary, title: "연락처에 저장하기", isEnabled: canConnect) {
                    viewModel.saveContactAndConnectFromSheet()
                },
                .init(kind: .primary, title: "연결만 하기", isEnabled: canConnect) {
                    viewModel.connectWithoutSavingFromSheet()
                }
            ]
        case .contactEditor:
            var actions: [SessionSettingsSheet.Action] = [
                .init(kind: .cancel, title: "취소", role: .cancel) {
                    viewModel.dismissSessionSettingsSheet()
                }
            ]
            if viewModel.isEditingContact {
                actions.append(
                    .init(kind: .secondary, title: "삭제", role: .destructive) {
                        viewModel.requestDeleteContactConfirmation()
                    }
                )
            }
            actions.append(
                .init(kind: .primary, title: viewModel.isEditingContact ? "저장" : "추가") {
                    viewModel.saveContactFromSheet()
                }
            )
            return actions
        }
    }
    
    var body: some View {
        VStack {
            VStack(spacing: 0) {
                MainWindowContentView()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .setupMainToolbar(for: .current)
        }
        .navigationBarTitleDisplayMode(.inline)
        .windowToolbarFullScreenVisibility(.automatic)
        .alert(isPresented: $viewModel.shouldDisplayErrorAlert) {
            let error = viewModel.errors.last
            
            return Alert(
                title: Text("오류 발생"),
                message: Text(error?.localizedDescription ?? "알 수 없는 오류가 발생했습니다."),
                dismissButton: .default(Text("확인")) {
                    viewModel.dismissLastError()
                }
            )
        }
        .sheet(isPresented: $viewModel.isSessionSettingsSheetPresented) {
            SessionSettingsSheet(
                scope: .session,
                sessionSettings: $viewModel.sessionSettingsDraft.settings,
                contactId: viewModel.sessionSettingsDraft.id,
                actions: sessionSettingsActions
            )
        }
        .alert("연락처 삭제", isPresented: $viewModel.isDeleteContactConfirmationPresented) {
            Button("삭제", role: .destructive) {
                viewModel.deleteContactFromSheet()
            }
            Button("취소", role: .cancel) {
                viewModel.cancelDeleteContactConfirmation()
            }
        } message: {
            Text("이 연락처를 삭제하면 복구할 수 없습니다.")
        }
        .setupClientPhaseHandler(client: viewModel.client) { phase in
            viewModel.handleClientPhaseChanged(phase)
        }
        .setupClientErrorHandler(client: viewModel.client) { error in
            viewModel.handleClientError(error)
        }
        .setupAuthChallengeHandler(client: viewModel.client)
        .setupClientStatisticsHandler(client: viewModel.client, viewModel: viewModel)
        .onAppear {
            viewModel.bind(settingsStore: settingsStore)
            viewModel.startContactObservation()
        }
        /*
        .onChange(of: self.scenePhase) { _, newPhase in
            if newPhase == .inactive {
                // will closed
                self.viewModel.stopSession()
            }
        }
         */

    }
}

typealias MainWindow = UIKitMainWindow

#Preview {
    UIKitMainWindow()
        .environmentObject(MainWindowViewModel())
        .environmentObject(SettingsStore())
}

#endif
