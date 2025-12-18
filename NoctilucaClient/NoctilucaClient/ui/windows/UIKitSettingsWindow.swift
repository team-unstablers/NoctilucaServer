//
//  Untitled.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/26/25.
//

#if os(iOS)

import SwiftUI

struct UIKitSettingsWindow: View {
    enum SettingsTab: Hashable {
        case general
        case projection
        case security
        case misc
        case plugins
        case about
    }
    
    
    @State
    private var selectedTab: SettingsTab = .general

    var body: some View {
        Form {
            Section {
                NavigationLink("일반", value: NavigationItem.settingsDetail(.general))
                NavigationLink("프로젝션", value: NavigationItem.settingsDetail(.general))
                NavigationLink("보안", value: NavigationItem.settingsDetail(.general))
                NavigationLink("기타", value: NavigationItem.settingsDetail(.general))
                NavigationLink("플러그인", value: NavigationItem.settingsDetail(.general))
                NavigationLink("정보", value: NavigationItem.settingsDetail(.general))
            }
        }
        .navigationTitle("설정")
    }
}

typealias SettingsWindow = UIKitSettingsWindow

#endif
