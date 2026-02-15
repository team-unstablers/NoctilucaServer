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
    var viewModel: SessionWindowViewModel
    
    @EnvironmentObject
    var contactSheetCoordinator: ContactSheetCoordinator

    @EnvironmentObject
    private var settingsStore: SettingsStore

    var body: some View {
        ZStack {
            VStack {
                VStack(spacing: 0) {
                    MainWindowContentView()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .setupMainToolbar(for: .current)
            }

            if viewModel.isFullscreen && viewModel.isFullscreenOverlayVisible {
                FullscreenOverlayView()
            }
        }
        .ignoresSafeArea(.all, edges: viewModel.isFullscreen ? .all : [])
        .statusBarHidden(viewModel.isFullscreen)
        .navigationBarTitleDisplayMode(.inline)
        .windowToolbarFullScreenVisibility(.automatic)
        .alert(isPresented: $viewModel.shouldDisplayErrorAlert) {
            let error = viewModel.errors.last

            return Alert(
                title: Text(error?.alertTitle ?? String(localized: "main.error.title", defaultValue: "오류 발생")),
                message: Text(error?.localizedDescription ?? String(localized: "main.error.unknown", defaultValue: "알 수 없는 오류가 발생했습니다.")),
                dismissButton: .default(Text(String(localized: "common.confirm", defaultValue: "확인"))) {
                    viewModel.dismissLastError()
                }
            )
        }
        .sheet(isPresented: $contactSheetCoordinator.isPresented, onDismiss: {
            viewModel.flushPendingConnectionErrors()
        }) {
            SessionSettingsSheet(
                scope: .session,
                sessionSettings: $contactSheetCoordinator.draft.settings,
                contactId: contactSheetCoordinator.mode == .quickConnect ? nil : contactSheetCoordinator.draft.id
            ) { action in
                switch action {
                case .cancel:
                    contactSheetCoordinator.dismiss()
                case .delete:
                    contactSheetCoordinator.delete()
                case .connect:
                    contactSheetCoordinator.connectWithoutSaving()
                case .saveAndConnect:
                    contactSheetCoordinator.saveAndConnect()
                case .save:
                    contactSheetCoordinator.save()
                }
            }
        }
    }
}

typealias MainWindow = UIKitMainWindow

#Preview {
    let viewModel = SessionWindowViewModel()
    UIKitMainWindow()
        .environmentObject(viewModel)
        .environmentObject(viewModel.contactSheetCoordinator)
        .environmentObject(SettingsStore.shared)
}

#endif
