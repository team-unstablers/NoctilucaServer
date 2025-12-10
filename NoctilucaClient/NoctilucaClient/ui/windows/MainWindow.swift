//
//  MainWindow.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import Foundation

import SwiftUI
import Combine

enum MainWindowPhase: Hashable {
    case newConnection
    case connecting
}

class MainWindowViewModel: ObservableObject {
    @State
    var phase: MainWindowPhase = .newConnection
}

struct MainWindow: View {
    @StateObject
    var viewModel = MainWindowViewModel()
    
    var body: some View {
        MainWindowContentView(viewModel: viewModel)
            .presentedWindowStyle(.titleBar)
            .presentedWindowToolbarStyle(.unified)
            .navigationTitle(NoctilucaMeta.productName)
    }
}
