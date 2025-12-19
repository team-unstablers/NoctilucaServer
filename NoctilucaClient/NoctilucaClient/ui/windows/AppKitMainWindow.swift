//
//  MainWindow.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

#if os(macOS)
import Foundation

import SwiftUI
import Combine

import SiriusKitClient

enum MainWindowPhase: Hashable {
    case newConnection
    case connecting
    case connected
}

struct AppKitMainWindow: View {
    @StateObject
    var viewModel = MainWindowViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            MainToolbar(addressBar: NSHostingView(rootView: AnyView(MainToolbarAddressBar(viewModel: viewModel))))
                .frame(width: 0, height: 0)
            
            MainWindowContentView()
                .frame(minWidth: 640, minHeight: 480)
                .presentedWindowStyle(.titleBar)
                .presentedWindowToolbarStyle(.unified)
                .navigationTitle(NoctilucaMeta.productName)
                .environmentObject(viewModel)
        }
        .windowToolbarFullScreenVisibility(.onHover)
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
        .setupClientPhaseHandler(client: viewModel.client) { phase in
            viewModel.handleClientPhaseChanged(phase)
        }
        .setupClientErrorHandler(client: viewModel.client) { error in
            viewModel.handleClientError(error)
        }
        .setupAuthChallengeHandler(client: viewModel.client)
        .setupClientStatisticsHandler(client: viewModel.client, viewModel: viewModel)
        .onAppear {
            self.viewModel.testKeyboard()
        }
    }
}

typealias MainWindow = AppKitMainWindow

#endif
