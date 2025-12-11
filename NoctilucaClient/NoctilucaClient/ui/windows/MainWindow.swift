//
//  MainWindow.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import Foundation

import SwiftUI
import Combine

import SiriusKitClient

enum MainWindowPhase: Hashable {
    case newConnection
    case connecting
}

struct MainWindow: View {
    @StateObject
    var viewModel = MainWindowViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            MainToolbar(addressBar: NSHostingView(rootView: AnyView(MainToolbarAddressBar(viewModel: viewModel))))
                .frame(width: 0, height: 0)
            
            MainWindowContentView(viewModel: viewModel)
                .frame(minWidth: 640, minHeight: 480)
                .presentedWindowStyle(.titleBar)
                .presentedWindowToolbarStyle(.unified)
                .navigationTitle(NoctilucaMeta.productName)
        }
    }
}
