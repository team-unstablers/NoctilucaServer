//
//  Untitled.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/26/25.
//

#if os(macOS)

import SwiftUI

struct AppKitSettingsWindow: View {
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
    
    @EnvironmentObject
    private var settingsStore: SettingsStore

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                GeneralSettingsTab()
                    .tabItem {
                        Text("일반")
                    }
                    .tag(SettingsTab.general)
                    .id(SettingsTab.general)
                ProjectionSettingsTab()
                    .tabItem {
                        Text("프로젝션")
                    }
                    .tag(SettingsTab.projection)
                    .id(SettingsTab.projection)
                InputSettingsTab(settings: $settingsStore.settings)
                    .tabItem {
                        Text("입력")
                    }
                    .tag(SettingsTab.input)
                    .id(SettingsTab.input)
                SecuritySettingsTab()
                    .tabItem {
                        Text("보안")
                    }
                    .tag(SettingsTab.security)
                    .id(SettingsTab.security)
                MiscSettingsTab()
                    .tabItem {
                        Text("기타")
                    }
                    .tag(SettingsTab.misc)
                    .id(SettingsTab.misc)
                PluginsSettingsTab()
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
        .environmentObject(settingsStore)
        .navigationTitle("test")
        .navigationSubtitle("test")
        .toolbar {
            /*
            ToolbarItem {
                Button("설정 저장", role: .confirm) {
                    do {
                        try server.settings.save()
                    } catch {
                        // FIXME: 다이얼로그를 띄우던 뭘 하던 하십시오
                        print(error)
                    }
                }
            }
             */
        }
    }
}

typealias SettingsWindow = AppKitSettingsWindow

#Preview {
    SettingsWindow()
        .environmentObject(SettingsStore.shared)
}

#endif
