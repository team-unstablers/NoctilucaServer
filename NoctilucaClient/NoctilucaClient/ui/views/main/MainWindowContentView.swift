//
//  MainWindowContentView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import SwiftUI

struct MainWindowContentView: View {
#if os(iOS)
    @Environment(\.horizontalSizeClass)
    var horizontalSizeClass
#endif

    @EnvironmentObject
    var viewModel: MainWindowViewModel

    var body: some View {
        switch viewModel.phase {
        case .newConnection:
            MainWindowNewConnectionPhaseContentView()
#if os(iOS)
                .safeAreaPadding(.vertical)
                .padding(.top, horizontalSizeClass == .compact ? 0 : 32)
#endif
        case .connecting:
            MainWindowConnectingPhaseContentView()
        case .connected:
            MainWindowMainPhaseContentView()
        default:
            EmptyView()
        }

    }
}
