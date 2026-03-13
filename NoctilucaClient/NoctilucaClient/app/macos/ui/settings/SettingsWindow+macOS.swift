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

    @EnvironmentObject
    private var settingsStore: SettingsStore

    @State
    private var selectedTab: SettingsTab = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label(String(localized: "settings.tabs.general", defaultValue: "일반"), systemImage: "gearshape")
                    .tag(SettingsTab.general)
                Label(String(localized: "settings.tabs.projection", defaultValue: "프로젝션"), systemImage: "rectangle.on.rectangle")
                    .tag(SettingsTab.projection)
                Label(String(localized: "settings.tabs.input", defaultValue: "입력"), systemImage: "keyboard")
                    .tag(SettingsTab.input)
                Label(String(localized: "settings.tabs.security", defaultValue: "보안"), systemImage: "lock")
                    .tag(SettingsTab.security)
                Label(String(localized: "settings.tabs.misc", defaultValue: "기타"), systemImage: "ellipsis.circle")
                    .tag(SettingsTab.misc)
                /*
                Label(String(localized: "settings.tabs.plugins", defaultValue: "플러그인"), systemImage: "puzzlepiece.extension")
                    .tag(SettingsTab.plugins)
                 */
                Label(String(localized: "settings.tabs.about", defaultValue: "정보"), systemImage: "info.circle")
                    .tag(SettingsTab.about)
            }
        } detail: {
            switch selectedTab {
            case .general:
                GeneralSettingsTab()
            case .projection:
                ProjectionSettingsTab()
            case .input:
                InputSettingsTab()
            case .security:
                SecuritySettingsTab()
            case .misc:
                MiscSettingsTab(settings: $settingsStore.settings)
            case .plugins:
                PluginsSettingsTab()
            case .about:
                AboutSettingsTab()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 640)
        .navigationSubtitle(String(localized: "settings.title", defaultValue: "설정"))
    }
}

typealias SettingsWindow = AppKitSettingsWindow

#Preview {
    SettingsWindow()
        .environmentObject(SettingsStore.shared)
}

#endif
