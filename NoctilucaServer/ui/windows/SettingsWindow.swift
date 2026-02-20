//
//  Untitled.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/26/25.
//

import SwiftUI

struct SettingsWindow: View {
    enum SettingsTab: Hashable {
        case general
        case projection
        case security
        case misc
        case plugins
        case about
    }
    
    @EnvironmentObject
    private var settingsStore: SettingsStore

    @State
    private var selectedTab: SettingsTab = .general

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                GeneralSettingsTab(settings: $settingsStore.settings)
                    .tabItem {
                        Text(markdown: String(localized: "settings.tab.general", defaultValue: "일반"))
                    }
                    .tag(SettingsTab.general)
                    .id(SettingsTab.general)
                ProjectionSettingsTab(settings: $settingsStore.settings)
                    .tabItem {
                        Text(markdown: String(localized: "settings.tab.projection", defaultValue: "프로젝션"))
                    }
                    .tag(SettingsTab.projection)
                    .id(SettingsTab.projection)
                SecuritySettingsTab(settings: $settingsStore.settings)
                    .tabItem {
                        Text(markdown: String(localized: "settings.tab.security", defaultValue: "보안"))
                    }
                    .tag(SettingsTab.security)
                    .id(SettingsTab.security)
                MiscSettingsTab(settings: $settingsStore.settings)
                    .tabItem {
                        Text(markdown: String(localized: "settings.tab.misc", defaultValue: "기타"))
                    }
                    .tag(SettingsTab.misc)
                    .id(SettingsTab.misc)
                PluginsSettingsTab(settings: $settingsStore.settings)
                    .tabItem {
                        Text(markdown: String(localized: "settings.tab.plugins", defaultValue: "플러그인"))
                    }
                    .tag(SettingsTab.plugins)
                    .id(SettingsTab.plugins)
                AboutSettingsTab()
                    .tabItem {
                        Text(markdown: String(localized: "settings.tab.about", defaultValue: "정보"))
                    }
                    .tag(SettingsTab.about)
                    .id(SettingsTab.about)
            }
            .frame(minWidth: 640)
        }
        .navigationTitle("test")
        .navigationSubtitle("test")
    }
}

#Preview {
    SettingsWindow()
}
