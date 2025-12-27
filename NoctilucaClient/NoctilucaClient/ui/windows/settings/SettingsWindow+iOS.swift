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
        case input
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
                NavigationLink("프로젝션", value: NavigationItem.settingsDetail(.projection))
                NavigationLink("입력", value: NavigationItem.settingsDetail(.input))
                NavigationLink("보안", value: NavigationItem.settingsDetail(.security))
                NavigationLink("기타", value: NavigationItem.settingsDetail(.misc))
                NavigationLink("플러그인", value: NavigationItem.settingsDetail(.plugins))
                NavigationLink("정보", value: NavigationItem.settingsDetail(.about))
            }
        }
        .navigationTitle("설정")
    }
}

typealias SettingsWindow = UIKitSettingsWindow

#endif
