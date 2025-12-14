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
                action: action
            ) { endpointURL in
                Task {
                    try await self.viewModel.startSession(endpointURL: endpointURL)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
}
