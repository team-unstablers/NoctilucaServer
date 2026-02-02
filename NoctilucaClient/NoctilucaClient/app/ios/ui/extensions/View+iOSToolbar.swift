//
//  View+setupAddressBar.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/20/25.
//

import SwiftUI

#if os(iOS)

extension View {
    @ViewBuilder
    func setupMainToolbar(for deviceKind: DeviceKind) -> some View {
        switch deviceKind {
        case .iPhone:
            self.modifier(ToolbarModifierIPhone())
        case .iPad:
            self.modifier(ToolbarModifierIPad())
        default:
            self.modifier(ToolbarModifierIPad())
        }
    }
}

struct ToolbarModifierIPhone: ViewModifier {
    @Environment(\.horizontalSizeClass)
    var horizontalSizeClass
    
    @EnvironmentObject
    var mobileUIMainViewModel: MobileUIMainViewModel

    @EnvironmentObject
    var viewModel: SessionWindowViewModel
    
    @EnvironmentObject
    private var settingsStore: SettingsStore
    
    @FocusState
    private var isAddressBarFocused: Bool

    func body(content: Content) -> some View {
        if horizontalSizeClass == .regular {
            content
                .safeAreaPadding(.horizontal)
                .modifier(ToolbarModifierIPad())
        } else {
            ZStack(alignment: .bottom) {
                content
                    .simultaneousGesture(TapGesture().onEnded {
                        isAddressBarFocused = false
                    })
                /*
                MainToolbarAddressBar(
                    viewModel: viewModel,
                    settingsStore: settingsStore,
                    focusBinding: $isAddressBarFocused
                )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                 */
            }
            .toolbar {
                if viewModel.phase == .newConnection {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            mobileUIMainViewModel.navState.append(.settings)
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            viewModel.contactSheetCoordinator.presentContactEditor(for: nil)
                        } label: {
                            Image(systemName: "plus.app")
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            Task { @MainActor in
                                await viewModel.stopSession()
                            }
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                    
                    if viewModel.phase == .connected {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                viewModel.shouldPresentDisplaySwitchSheet = true
                            } label: {
                                Image(systemName: "display.2")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.foreground, .clear)
                                    .frame(width: 28, height: 28)
                            }
                        }
                    }
                }
            }
        }
    }
}


struct ToolbarModifierIPad: ViewModifier {
    @EnvironmentObject
    var mobileUIMainViewModel: MobileUIMainViewModel
    
    @EnvironmentObject
    var viewModel: SessionWindowViewModel
    
    @EnvironmentObject
    private var settingsStore: SettingsStore
    
    @State
    var principalFrame: CGRect = .init(x: 320, y: 240, width: 1, height: 1)
    
    @State
    var toolbarStyle: MainWindowToolbarStyle = .compact

    @State
    var shouldPresentAddressBar: Bool = false
    
    @FocusState
    var isAddressBarFocused: Bool

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top) {
                HStack {
                    MainToolbarAddressBar(
                        viewModel: viewModel,
                        settingsStore: settingsStore,
                        focusBinding: .none
                    )
                    .allowsHitTesting(false)
                    .opacity(isAddressBarFocused ? 0.001 : 1.0)
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
                .ignoresSafeArea()
                // .background(.blue)
                .frame(maxHeight: 0)
            }
            .if(shouldPresentAddressBar) {
                $0.overlay {
                    ZStack {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture {
                                isAddressBarFocused = false
                            }
                        
                        HStack {
                            MainToolbarAddressBar(
                                viewModel: viewModel,
                                settingsStore: settingsStore,
                                focusBinding: $isAddressBarFocused
                            )
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
                    .ignoresSafeArea(.all)
                    .background(.ultraThinMaterial)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        .ignoresSafeArea(.container, edges: .bottom)
        // .ignoresSafeArea(.all)
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
                
                if viewModel.phase == .newConnection {
                    let toolbarPlacement: ToolbarItemPlacement = (toolbarStyle == .standard) ? .topBarTrailing : .bottomBar
                    ToolbarItem(placement: toolbarPlacement) {
                        Button {
                            mobileUIMainViewModel.navState.append(.settings)
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                    ToolbarItem(placement: toolbarPlacement) {
                        Button {
                            viewModel.contactSheetCoordinator.presentContactEditor(for: nil)
                        } label: {
                            Image(systemName: "plus.app")
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            Task { @MainActor in
                                await viewModel.stopSession()
                            }
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                    
                    if viewModel.phase == .connected {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                viewModel.shouldPresentDisplaySwitchSheet = true
                            } label: {
                                Image(systemName: "display.2")
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .foregroundStyle(.foreground, .clear)
                                    .frame(width: 28, height: 28)
                            }
                        }
                    }
                }
            }
        }

        
    }
}

#endif
