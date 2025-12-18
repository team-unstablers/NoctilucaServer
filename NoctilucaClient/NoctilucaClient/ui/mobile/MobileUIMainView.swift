//
//  MobileUIMain.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/17/25.
//

#if os(iOS)
import SwiftUI

enum NavigationItem: Hashable {
    case settings
    case settingsDetail(SettingsWindow.SettingsTab)
}

struct MobileUIMainView: View {
    @State
    var navState: [NavigationItem] = []
    
    var body: some View {
        NavigationStack(path: $navState) {
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
