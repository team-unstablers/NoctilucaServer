//
//  Untitled.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/26/25.
//

import SwiftUI
import Inject

struct SettingsWindow: View {
    enum SettingsTab: Hashable {
        case general
        case projection
        case appStream
        case security
        case transfer
        case fileAccess
        case misc
        case plugins
        case about
    }
    
    @ObserveInjection
    var inject

    @EnvironmentObject
    private var settingsStore: SettingsStore

    @State
    private var selectedTab: SettingsTab = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                Label(String(localized: "settings.tab.general", defaultValue: "일반"), systemImage: "gearshape")
                    .tag(SettingsTab.general)
                Label(String(localized: "settings.tab.security", defaultValue: "보안"), systemImage: "lock")
                    .tag(SettingsTab.security)
                Label(String(localized: "settings.tab.projection", defaultValue: "프로젝션"), systemImage: "rectangle.on.rectangle")
                    .tag(SettingsTab.projection)
                Label(String(localized: "settings.tab.app_stream", defaultValue: "AppStream"), systemImage: "app")
                    .tag(SettingsTab.appStream)
                Label(String(localized: "settings.tab.security", defaultValue: "보안"), systemImage: "lock")
                    .tag(SettingsTab.security)
                Label(String(localized: "settings.tab.transfer", defaultValue: "데이터 전송"), systemImage: "arrow.up.arrow.down")
                    .tag(SettingsTab.transfer)
                Label(String(localized: "settings.tab.file_access", defaultValue: "파일 시스템 마운트"), systemImage: "externaldrive.badge.plus")
                    .tag(SettingsTab.fileAccess)
                Label(String(localized: "settings.tab.misc", defaultValue: "기타"), systemImage: "ellipsis.circle")
                    .tag(SettingsTab.misc)
                Label(String(localized: "settings.tab.plugins", defaultValue: "플러그인"), systemImage: "puzzlepiece.extension")
                    .tag(SettingsTab.plugins)
                Label(String(localized: "settings.tab.about", defaultValue: "정보"), systemImage: "info.circle")
                    .tag(SettingsTab.about)
            }
        } detail: {
            switch selectedTab {
            case .general:
                GeneralSettingsTab(settings: $settingsStore.settings)
            case .projection:
                ProjectionSettingsTab(settings: $settingsStore.settings)
            case .appStream:
                AppStreamSettingsTab(settings: $settingsStore.settings)
            case .security:
                SecuritySettingsTab(settings: $settingsStore.settings)
            case .transfer:
                TransferSettingsTab(settings: $settingsStore.settings)
            case .fileAccess:
                FileAccessSettingsTab(settings: $settingsStore.settings)
            case .misc:
                MiscSettingsTab(settings: $settingsStore.settings)
            case .plugins:
                PluginsSettingsTab(settings: $settingsStore.settings)
            case .about:
                AboutSettingsTab()
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
        .frame(minWidth: 640)
        .navigationSubtitle(String(localized: "settings.title", defaultValue: "설정"))
        .enableInjection()
    }
}

#Preview {
    SettingsWindow()
}
