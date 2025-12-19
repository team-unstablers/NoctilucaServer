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

enum MainWindowPhase: Hashable {
    case newConnection
    case connecting
    case connected
}

enum MainWindowToolbarStyle {
    case standard
    case compact
}

struct UIKitMainWindow: View {
    @EnvironmentObject
    var viewModel: MainWindowViewModel
    
    @State
    var principalFrame: CGRect = .init(x: 320, y: 240, width: 1, height: 1)
    
    @State
    var shouldPresentAddressBar: Bool = false
    
    @State
    var toolbarStyle: MainWindowToolbarStyle = .compact
    
    @FocusState
    var isAddressBarFocused: Bool
    
    var body: some View {
        VStack {
            VStack(spacing: 0) {
                MainWindowContentView()
                    .environmentObject(viewModel)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .if(shouldPresentAddressBar) {
                $0.overlay {
                    HStack {
                        MainToolbarAddressBar(viewModel: viewModel)
                            .focused($isAddressBarFocused)
                            .onAppear {
                                isAddressBarFocused = true
                            }
                            .onChange(of: isAddressBarFocused) { oldValue, newValue in
                                if (newValue == false) {
                                    shouldPresentAddressBar = false
                                }
                            }
                    }
                    .if(toolbarStyle == .standard) {
                        $0
                            .frame(maxWidth: 400)
                            .position(x: principalFrame.midX, y: principalFrame.midY)
                    }
                    .if(toolbarStyle == .compact) {
                        $0
                            .frame(maxWidth: 400)
                            .position(x: principalFrame.midX, y: principalFrame.midY)
                    }
                }
            }
            .if(!shouldPresentAddressBar) {
                $0.overlay {
                    HStack {
                        MainToolbarAddressBar(viewModel: viewModel)
                            .allowsHitTesting(false)
                            .opacity(1.0)
                    }
                    .if(toolbarStyle == .standard) {
                        $0
                            .frame(maxWidth: 400)
                            .position(x: principalFrame.midX, y: principalFrame.midY)
                    }
                    .if(toolbarStyle == .compact) {
                        $0
                            .frame(maxWidth: 400)
                            .position(x: principalFrame.midX, y: principalFrame.midY)
                    }
                }
            }
        }
        .ignoresSafeArea(.all)
        .onGeometryChange(for: CGSize.self) {
            return $0.size
        } action: {
            if $0.width <= 650 {
                toolbarStyle = .compact
            } else {
                toolbarStyle = .standard
            }
        }
        .if(!shouldPresentAddressBar) {
            $0.toolbar {
                ToolbarItem(placement: .principal) {
                    Button {
                        shouldPresentAddressBar = true
                    } label: {
                        Text("...")
                            .opacity(0.001)
                            .frame(width: 400, height: 38)
                            .overlay {
                                GeometryReader { geom in
                                    Text("test")
                                        .opacity(0.001)
                                        .onAppear {
                                            principalFrame = geom.frame(in: .global)
                                        }
                                        .onChange(of: geom.frame(in: .global)) { _, newFrame in
                                            principalFrame = newFrame
                                        }
                                }
                            }
                    }
                    .frame(width: 400, height: 38)
                }
                
                let toolbarPlacement: ToolbarItemPlacement = (toolbarStyle == .standard) ? .topBarTrailing : .bottomBar
                ToolbarItem(placement: toolbarPlacement) {
                    Button {
                        // navState.append(.settings)
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: toolbarPlacement) {
                    Button {
                        
                    } label: {
                        Image(systemName: "plus.app")
                    }
                }
            }
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
        .setupClientPhaseHandler(client: viewModel.client) { phase in
            viewModel.handleClientPhaseChanged(phase)
        }
        .setupClientErrorHandler(client: viewModel.client) { error in
            viewModel.handleClientError(error)
        }
        .setupAuthChallengeHandler(client: viewModel.client)
        .setupClientStatisticsHandler(client: viewModel.client, viewModel: viewModel)
        /*
        .onChange(of: self.scenePhase) { _, newPhase in
            if newPhase == .inactive {
                // will closed
                self.viewModel.stopSession()
            }
        }
         */

    }
}

typealias MainWindow = UIKitMainWindow

#Preview {
    UIKitMainWindow()
}

#endif
