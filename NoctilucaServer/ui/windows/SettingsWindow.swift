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
        case display
        case security
        case misc
        case plugins
        case about
    }
    
    @State
    private var settings: AppSettings = .init()

    @State
    private var selectedTab: SettingsTab = .general

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                SettingsGeneralTab(settings: $settings)
                    .tabItem {
                        Text("일반")
                    }
                    .tag(SettingsTab.general)
                    .id(SettingsTab.general)
                DisplaySettingsTab()
                    .tabItem {
                        Text("화면")
                    }
                    .tag(SettingsTab.display)
                    .id(SettingsTab.display)
                SecuritySettingsTab(settings: $settings)
                    .tabItem {
                        Text("보안")
                    }
                    .tag(SettingsTab.security)
                    .id(SettingsTab.security)
                MiscSettingsTab(settings: $settings)
                    .tabItem {
                        Text("기타")
                    }
                    .tag(SettingsTab.misc)
                    .id(SettingsTab.misc)
                PluginsSettingsTab(settings: $settings)
                    .tabItem {
                        Text("플러그인")
                    }
                    .tag(SettingsTab.plugins)
                    .id(SettingsTab.plugins)
                AboutSettingsTab()
                    .tabItem {
                        Text("정보")
                    }
                    .tag(SettingsTab.about)
                    .id(SettingsTab.about)
            }
            .frame(minWidth: 640)
        }
        .navigationTitle("test")
        .navigationSubtitle("test")
        .toolbar {
            ToolbarItem {
                Button("설정 저장", role: .confirm) {
                }
            }
        }
    }
}

#Preview {
    SettingsWindow()
}
