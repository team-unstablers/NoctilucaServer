//
//  MobileUIMain.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/17/25.
//

#if os(tvOS)
import SwiftUI

struct TVUIMainView: View {
    @EnvironmentObject
    var viewModel: MobileUIMainViewModel
    
    var body: some View {
        NavigationStack(path: $viewModel.navState) {
            MainWindow()
                .navigationDestination(for: NavigationItem.self) { item in
                    switch item {
                    case .settings:
                        SettingsWindow()
                    case .settingsDetail(let tab):
                        switch tab {
                        case .general:
                            GeneralSettingsTab()
                        case .projection:
                            ProjectionSettingsTab()
                        case .input:
                            InputSettingsTab()
                        case .security:
                            SecuritySettingsTab()
                        case .misc:
                            MiscSettingsTab()
                        case .plugins:
                            PluginsSettingsTab()
                        case .about:
                            AboutSettingsTab()
                        }
                    case .sessionSettings(let contactId):
                        SessionSettingsSheet(
                            scope: .session,
                            sessionSettings: $viewModel.sessionSettingsDraft.settings,
                            contactId: viewModel.sessionSettingsSheetMode == .quickConnect ? nil : viewModel.sessionSettingsDraft.id,
                        ) { action in
                            switch action {
                            case .cancel:
                                viewModel
                            case .delete:
                                viewModel.cancelDeleteContactConfirmation()
                            case .connect:
                                viewModel.connectWithoutSavingFromSheet()
                            case .saveAndConnect:
                                viewModel.saveContactAndConnectFromSheet()
                            case .save:
                                viewModel.saveContactFromSheet()
                            }
                            
                            viewModel.dismissSessionSettingsSheet()
                        }
                    }
                }
        }
    }
}

typealias MobileUIMainView = TVUIMainView

#Preview {
    MobileUIMainView()
}

#endif
