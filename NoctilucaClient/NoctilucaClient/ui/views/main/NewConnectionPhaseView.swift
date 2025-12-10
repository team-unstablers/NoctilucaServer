//
//  NewConnectionPhaseView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import Foundation

import SwiftUI
import Combine

struct NewConnectionPhaseView: View {
    @ObservedObject
    var viewModel: MainWindowViewModel
    
    @State
    var expertMode: Bool = false
    
    @State
    var endpointURL: String = ""
    
    
    var phaseTitle: String {
        String(localized: "ui.window.main.new_connection_phase.title", defaultValue: "새 연결")
    }
    
    var body: some View {
        VStack {
            VStack(spacing: 12) {
                VStack {
                    TextField("원격 호스트 주소", text: $endpointURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 16))
                }
                HStack {
                    Spacer()
                    Button("접속") {
                        
                    }
                }
            }
            .padding(8)
        }
        .padding(16)
        .frame(minWidth: 480)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                if !expertMode {
                    Button("고급 모드") {
                        expertMode = true
                    }
                } else {
                    Button("간단 모드") {
                        expertMode = false
                    }
                }
            }
        }
        .navigationSubtitle(phaseTitle)
    }
}

#Preview {
    let viewModel = MainWindowViewModel()
    
    NewConnectionPhaseView(viewModel: viewModel)
        .presentedWindowStyle(.titleBar)
        .presentedWindowToolbarStyle(.unified)
        .navigationTitle(NoctilucaMeta.productName)
}
