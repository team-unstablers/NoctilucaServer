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
    private var server: NoctilucaServer
    
    @State
    private var selectedTab: SettingsTab = .general

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedTab) {
                SettingsGeneralTab(settings: $server.settings)
                    .tabItem {
                        Text("일반")
                    }
                    .tag(SettingsTab.general)
                    .id(SettingsTab.general)
                ProjectionSettingsTab(settings: $server.settings)
                    .tabItem {
                        Text("프로젝션")
                    }
                    .tag(SettingsTab.projection)
                    .id(SettingsTab.projection)
                SecuritySettingsTab(settings: $server.settings)
                    .tabItem {
                        Text("보안")
                    }
                    .tag(SettingsTab.security)
                    .id(SettingsTab.security)
                MiscSettingsTab(settings: $server.settings)
                    .tabItem {
                        Text("기타")
                    }
                    .tag(SettingsTab.misc)
                    .id(SettingsTab.misc)
                PluginsSettingsTab(settings: $server.settings)
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
                Button("설정 저장", role: .compatibleConfirm) {
                    do {
                        try server.settings.save()
                    } catch {
                        // FIXME: 다이얼로그를 띄우던 뭘 하던 하십시오
                        print(error)
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsWindow()
}
