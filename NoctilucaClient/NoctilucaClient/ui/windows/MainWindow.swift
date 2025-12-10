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
    
}

struct MainWindow: View {
    @State
    var phase: MainWindowPhase = .newConnection
    
    @StateObject
    var viewModel = MainWindowViewModel()
    
    @ViewBuilder
    private var _body: some View {
        switch phase {
        case .newConnection:
            NewConnectionPhaseView(viewModel: viewModel)
        default:
            Text("준비 중...")
        }
    }
    
    var body: some View {
        _body
            .presentedWindowStyle(.titleBar)
            .presentedWindowToolbarStyle(.unified)
            .navigationTitle(NoctilucaMeta.productName)
    }
}
