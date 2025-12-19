//
//  MobileUIMainViewModel.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/19/25.
//

#if os(iOS)

import Foundation
import Combine

enum NavigationItem: Hashable {
    case settings
    case settingsDetail(SettingsWindow.SettingsTab)
}

class MobileUIMainViewModel: ObservableObject {
    @Published
    var navState: [NavigationItem] = []
}

#endif
