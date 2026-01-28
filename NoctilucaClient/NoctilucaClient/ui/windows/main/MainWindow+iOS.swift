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
        .sheet(isPresented: $viewModel.contactSheetCoordinator.isPresented) {
            let coordinator = viewModel.contactSheetCoordinator
            SessionSettingsSheet(
                scope: .session,
                sessionSettings: $viewModel.contactSheetCoordinator.draft.settings,
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
        .onAppear {
            viewModel.bind(settingsStore: settingsStore)
            viewModel.loadContacts()
        }
    }
}

typealias MainWindow = UIKitMainWindow

#Preview {
    UIKitMainWindow()
        .environmentObject(MainWindowViewModel())
        .environmentObject(SettingsStore.shared)
}

#endif
