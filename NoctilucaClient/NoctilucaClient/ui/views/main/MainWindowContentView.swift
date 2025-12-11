//
//  NewConnectionPhaseView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import Foundation

import SwiftUI
import Combine

import SiriusKitClient

struct MainWindowNewConnectionPhaseContentView: View {
    @ObservedObject
    var viewModel: MainWindowViewModel
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 0) {
                Text("Noctiluca ")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Navigator")
                    .font(.largeTitle)
                    .fontWeight(.light)
            }
            
            Text("버전 \(NoctilucaMeta.version)")
                .padding(.bottom, 32)
            
            
            Text("최근 연결한 호스트 목록이 없습니다.\n주소 표시줄에 연결하고자 하는 호스트 주소를 입력해 주세요.")
            
            VStack {
            }
            .frame(maxWidth: .infinity)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MainWindowConnectingPhaseContentView: View {
    @ObservedObject
    var viewModel: MainWindowViewModel
    
    @State
    var isLogAreaVisible: Bool = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(alignment: .leading) {
                
                Spacer()
                
                HStack(spacing: 0) {
                    Text("연결 중")
                        .font(.largeTitle)
                        .fontWeight(.light)
                }
                .padding(.bottom, 2)
                
                Text("\(self.viewModel.endpointURL)에 연결하고 있습니다...")
                    .padding(.bottom, 32)
                
                Spacer()
                
                
                VStack {
                }
                .frame(maxWidth: .infinity)
            }
            
            
                Text(
                    self.viewModel.connectionLog.joined(separator: "\n")
                )
                .font(.system(size: 12).monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color(NSColor.windowBackgroundColor),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .opacity(isLogAreaVisible ? 0.0 : 1.0)
                }
                .onHover { hoverState in
                    if hoverState {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLogAreaVisible = true
                        }
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLogAreaVisible = false
                        }
                    }
                    
                }
        }
        .padding(24)
    }
}


struct MainWindowContentView: View {
    @ObservedObject
    var viewModel: MainWindowViewModel
    
    @State
    var expertMode: Bool = false
    
    @State
    var endpointURL: String = ""
    
    var body: some View {
        switch viewModel.phase {
        case .newConnection:
            MainWindowNewConnectionPhaseContentView(viewModel: viewModel)
        case .connecting:
            MainWindowConnectingPhaseContentView(viewModel: viewModel)
        default:
            EmptyView()
        }
        
    }
}

#Preview("NewConnectionPhase") {
    let viewModel = MainWindowViewModel()
    
    /*
    MainWindowContentView(viewModel: viewModel)
     */
    
    MainWindowNewConnectionPhaseContentView(viewModel: viewModel)
        .frame(minWidth: 640, minHeight: 480)
}

#Preview("ConnectingPhase") {
    let viewModel = MainWindowViewModel()
    
    MainWindowConnectingPhaseContentView(viewModel: viewModel)
        .frame(minWidth: 640, minHeight: 480)
}
