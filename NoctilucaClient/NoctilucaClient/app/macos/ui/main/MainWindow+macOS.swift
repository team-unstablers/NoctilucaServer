//
//  AppKitMainWindow.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

#if os(macOS)
import AppKit
import SwiftUI

struct MainWindowRootView: View {
    @Bindable
    var viewModel: SessionWindowViewModel

    @EnvironmentObject
    var contactSheetCoordinator: ContactSheetCoordinator

    @EnvironmentObject
    private var settingsStore: SettingsStore

    /*
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
     */
    
    var body: some View {
        MainWindowContentView()
            .frame(minWidth: 640, minHeight: 480)
            .environment(viewModel)
            .alert(isPresented: $viewModel.shouldDisplayErrorAlert) {
                let error = viewModel.errors.last

                return Alert(
                    title: Text(error?.alertTitle ?? String(localized: "main.error.title", defaultValue: "오류 발생")),
                    message: Text(error?.localizedDescription ?? String(localized: "main.error.unknown", defaultValue: "알 수 없는 오류가 발생했습니다.")),
                    dismissButton: .default(Text(markdown: String(localized: "common.confirm", defaultValue: "확인"))) {
                        viewModel.dismissLastError()
                    }
                )
            }
            .sheet(isPresented: $contactSheetCoordinator.isPresented, onDismiss: {
                viewModel.flushPendingConnectionErrors()
            }) {
                let coordinator = contactSheetCoordinator
                SessionSettingsSheet(
                    scope: .session,
                    sessionSettings: $contactSheetCoordinator.draft.settings,
                    contactId: coordinator.mode == .quickConnect ? nil : coordinator.draft.id
                ) { action in
                    switch action {
                    case .cancel:
                        coordinator.dismiss()
                    case .delete:
                        coordinator.delete()
                    case .connect:
                        coordinator.connectWithoutSaving()
                    case .saveAndConnect:
                        coordinator.saveAndConnect()
                    case .save:
                        coordinator.save()
                    }
                }
            }
    }
}
#endif
