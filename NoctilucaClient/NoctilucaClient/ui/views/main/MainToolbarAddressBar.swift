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
        case .connecting:
            return .connecting(progress: 0.1)
        }
    }
    
    var body: some View {
        VStack {
            let action = self.action
            
            AddressBar(
                endpointURL: viewModel.endpointURL,
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
