//
//  MobileUIMain.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/17/25.
//

#if os(iOS)
import SwiftUI

struct MobileUIMainView: View {
    @EnvironmentObject
    var viewModel: MobileUIMainViewModel
    
    var body: some View {
        NavigationStack(path: $viewModel.navState) {
            MainWindow()
            /*
                .toolbar {

                }
             */
                .navigationDestination(for: NavigationItem.self) { item in
                    switch item {
                    case .settings:
                        SettingsWindow()
                    case .settingsDetail(let tab):
                        AboutSettingsTab()
                    }
                }
        }
    }
}

#Preview {
    MobileUIMainView()
}

#endif
