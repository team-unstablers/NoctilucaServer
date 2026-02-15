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
                NavigationLink(String(localized: "settings.tabs.general", defaultValue: "일반"), value: NavigationItem.settingsDetail(.general))
                NavigationLink(String(localized: "settings.tabs.projection", defaultValue: "프로젝션"), value: NavigationItem.settingsDetail(.projection))
                NavigationLink(String(localized: "settings.tabs.input", defaultValue: "입력"), value: NavigationItem.settingsDetail(.input))
                NavigationLink(String(localized: "settings.tabs.security", defaultValue: "보안"), value: NavigationItem.settingsDetail(.security))
                NavigationLink(String(localized: "settings.tabs.misc", defaultValue: "기타"), value: NavigationItem.settingsDetail(.misc))
                NavigationLink(String(localized: "settings.tabs.plugins", defaultValue: "플러그인"), value: NavigationItem.settingsDetail(.plugins))
                NavigationLink(String(localized: "settings.tabs.about", defaultValue: "정보"), value: NavigationItem.settingsDetail(.about))
            }
        }
        .navigationTitle(String(localized: "settings.title", defaultValue: "설정"))
    }
}

typealias SettingsWindow = UIKitSettingsWindow

#endif
