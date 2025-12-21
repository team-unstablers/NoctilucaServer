//
//  SessionSettingsSheet.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import SwiftUI

private struct SessionSettingsScopeKey: EnvironmentKey {
    static let defaultValue = SessionSettingsScope.global
}

extension EnvironmentValues {
    var sessionSettingsScope: SessionSettingsScope {
        get { self[SessionSettingsScopeKey.self] }
        set { self[SessionSettingsScopeKey.self] = newValue }
    }
}

struct SessionSettingsSheet: View {
    enum SettingsTab: Hashable {
        case general
        case projection
        case security
    }
    
    let scope: SessionSettingsScope
    
    @State
    private var selectedTab: SettingsTab = .general

    init(scope: SessionSettingsScope = .global) {
        self.scope = scope
    }
    
    @ViewBuilder
    var _body: some View {
        TabView(selection: $selectedTab) {
            /*
            if scope == .session {
                GeneralSettingsTab()
                    .tabItem {
                        Text("일반")
                    }
                    .tag(SettingsTab.general)
                    .id(SettingsTab.general)
            }
             */
            ProjectionSessionSettingsTab()
                .tabItem {
                    Text("프로젝션")
                }
                .tag(SettingsTab.projection)
                .id(SettingsTab.projection)
            SecuritySessionSettingsTab()
                .tabItem {
                    Text("보안")
                }
                .tag(SettingsTab.security)
                .id(SettingsTab.security)
 
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(\.sessionSettingsScope, scope)
    }
    
#if os(macOS)
    var body: some View {
        _body
    }
#else
    var body: some View {
        NavigationStack {
            _body
                .navigationTitle("세션 설정")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                    
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .confirm) {
                        } label: {
                            Image(systemName: "checkmark")
                        }
                    }
                }
        }
        .interactiveDismissDisabled()
    }
#endif
}

#Preview {
    SessionSettingsSheet()
        .frame(minHeight: 720)
        .environmentObject(SessionSettingsStore(loadFromDisk: false))
}
