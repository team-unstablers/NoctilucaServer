//
//  MainToolbarAddressBar.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import SwiftUI

import SiriusKitClient

struct MainToolbarAddressBar: View {
    @ObservedObject
    var viewModel: SessionWindowViewModel

    @ObservedObject
    var settingsStore: SettingsStore
    
    private let focusBinding: FocusState<Bool>.Binding?
    
    @FocusState
    private var internalFocus: Bool
    
    var pingRTT: Double? {
        viewModel.pingRTT
    }
    
    init(viewModel: SessionWindowViewModel,
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
    
    var degradationIndicator: AddressBarDegradationIndicatorState? {
        if case .newConnection = viewModel.phase {
            return nil
        }

        guard let notice = viewModel.degradationNotice else {
            return nil
        }

        return AddressBarDegradationIndicatorState(
            reasons: .init(rawValue: notice.reason.rawValue),
            types: .init(rawValue: notice.type.rawValue),
            additionalInfo: .init(rawValue: notice.additionalInfo.rawValue)
        )
    }

    var qualityIndicator: AddressBarQualityIndicatorState? {
        if case .newConnection = viewModel.phase {
            return nil
        }
        
        guard let pingRTT = pingRTT else {
            return .unknown
        }

        
        switch pingRTT {
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
    }
    
    var body: some View {
        VStack {
            let action = self.action
            
            AddressBar(
                endpointURL: viewModel.endpointURL,
                securityIndicator: securityIndicator,
                qualityIndicator: qualityIndicator,
                degradationIndicator: degradationIndicator,
                rtt: viewModel.pingRTT ?? 0.0,
                action: action,
                isFocused: resolvedFocusBinding
            ) { action in
                switch action {
                case .cancel:
                    return
                case .submit(let endpoint):
                    switch endpoint {
                    case .connect(let endpointURL):
                        viewModel.contactSheetCoordinator.presentQuickConnect(endpointURL: endpointURL)
                    case .contact, .quickConnect:
                        Task { @MainActor in
                            try await self.viewModel.startSession(endpoint: endpoint)
                        }
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
    var viewModel: SessionWindowViewModel
    
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
    let viewModel = SessionWindowViewModel()
    
    VStack {
        Spacer()
        
        UIKitStyledMainToolbarAddressBar(viewModel: viewModel)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.red)
    .environmentObject(SettingsStore.shared)
}

#endif
