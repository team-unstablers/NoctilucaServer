//
//  MainWindow.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

#if os(tvOS)
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
            .setupMainToolbar(for: .tv)
        }
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
        /*
        .fullScreenCover(isPresented: $viewModel.isSessionSettingsSheetPresented) {

            .background(.background)
        }
         */
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
    }
}

typealias MainWindow = UIKitMainWindow

#Preview {
    UIKitMainWindow()
        .environmentObject(MainWindowViewModel())
        .environmentObject(SettingsStore.shared)
}

#endif
