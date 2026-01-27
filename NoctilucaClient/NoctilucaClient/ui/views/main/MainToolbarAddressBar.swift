//
//  MainToolbarAddressBar.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import SwiftUI

struct MainToolbarAddressBar: View {
    @ObservedObject
    var viewModel: MainWindowViewModel

    @ObservedObject
    var settingsStore: SettingsStore
    
    private let focusBinding: FocusState<Bool>.Binding?
    
    @FocusState
    private var internalFocus: Bool
    
    init(viewModel: MainWindowViewModel,
         settingsStore: SettingsStore,
         focusBinding: FocusState<Bool>.Binding? = nil) {
        self._viewModel = ObservedObject(wrappedValue: viewModel)
        self._settingsStore = ObservedObject(wrappedValue: settingsStore)
        self.focusBinding = focusBinding
    }
    
    private var resolvedFocusBinding: FocusState<Bool>.Binding {
        focusBinding ?? $internalFocus
    }
    
    var action: AddressBarActionState? {
        switch viewModel.phase {
        case .newConnection:
            return nil
        case .connected:
            return nil
        case .connecting:
            return .connecting(progress: 0.1)
        }
    }
    
    var securityIndicator: AddressBarSecurityIndicatorState? {
        if case .newConnection = viewModel.phase {
            return nil
        }
        
        return .neutral
    }
    
    var qualityIndicator: AddressBarQualityIndicatorState? {
        if case .newConnection = viewModel.phase {
            return nil
        }
        
        switch viewModel.averagePingRTT {
        // ~50ms: excellent
        case 0..<0.050:
            return .excellent
            
        // ~100ms: good
        case 0.050..<0.100:
            return .good
            
        // ~200ms: bad
        case 0.100..<0.200:
            return .bad
            
        // >200ms: poor
        default:
            return .poor
        }
            
        return .unknown
    }
    
    var body: some View {
        VStack {
            let action = self.action
            
            AddressBar(
                endpointURL: viewModel.endpointURL,
                securityIndicator: securityIndicator,
                qualityIndicator: qualityIndicator,
                rtt: viewModel.averagePingRTT,
                action: action,
                isFocused: resolvedFocusBinding
            ) { endpoint in
                guard let endpoint else {
                    return
                }

                switch endpoint {
                case .connect(let endpointURL):
                    viewModel.contactSheetCoordinator.presentQuickConnect(endpointURL: endpointURL)
                case .contact, .quickConnect:
                    Task {
                        try await self.viewModel.startSession(endpoint: endpoint)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}

#if os(iOS)

struct UIKitStyledMainToolbarAddressBar: View {
    @ObservedObject
    var viewModel: MainWindowViewModel
    
    @EnvironmentObject
    private var settingsStore: SettingsStore
    
    var body: some View {
        VStack(spacing: 8) {
            MainToolbarAddressBar(viewModel: viewModel, settingsStore: settingsStore)
            HStack(spacing: 16) {
                Spacer()
                
                Button {
                    
                } label: {
                    Image(systemName: "keyboard")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.foreground)
                        .frame(width: 24, height: 24)
                }
                
                Button {
                    
                } label: {
                    Image(systemName: "chevron.down")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.foreground)
                        .frame(width: 24, height: 24)
                }
            }
        }
        
        .padding(16)
        .background(.white)
        // .safeAreaPadding(.bottom)
    }
}

#Preview {
    let viewModel = MainWindowViewModel()
    
    VStack {
        Spacer()
        
        UIKitStyledMainToolbarAddressBar(viewModel: viewModel)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.red)
    .environmentObject(SettingsStore.shared)
}

#endif
