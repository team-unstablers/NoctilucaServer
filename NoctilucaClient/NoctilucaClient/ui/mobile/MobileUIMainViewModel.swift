//
//  MobileUIMainViewModel.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/19/25.
//

#if os(iOS) || os(tvOS)
import Foundation
import Combine

enum NavigationItem: Hashable {
    case settings
    case settingsDetail(SettingsWindow.SettingsTab)
#if os(tvOS)
    case sessionSettings(UUID)
#endif
}

class MobileUIMainViewModel: ObservableObject {
    @Published
    var navState: [NavigationItem] = []
}

#endif
