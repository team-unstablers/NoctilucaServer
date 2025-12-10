//
//  NewConnectionPhaseView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import Foundation

import SwiftUI
import Combine

struct MainWindowContentView: View {
    @ObservedObject
    var viewModel: MainWindowViewModel
    
    @State
    var expertMode: Bool = false
    
    @State
    var endpointURL: String = ""
    
    
    var phaseTitle: String {
        String(localized: "ui.window.main.new_connection_phase.title", defaultValue: "새 연결")
    }
    
    @ViewBuilder
    var toolbar: some View {
        VStack {
            AddressBar(securityIndicator: .trustable, qualityIndicator: .excellent)
        }
        .frame(maxWidth: .infinity)
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                MainToolbar(addressBar: NSHostingView(rootView: AnyView(self.toolbar)))
                    .frame(width: 0, height: 0)
                
                HStack {
                    Spacer()
                }
            }
            .padding(8)
        }
        .padding(16)
        .frame(minWidth: 640)
        .navigationSubtitle(phaseTitle)
    }
}

#Preview {
    let viewModel = MainWindowViewModel()
    
    MainWindowContentView(viewModel: viewModel)
}
