//
//  SessionSettingsSheet.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import SwiftUI

struct SessionSettingsSheet: View {
    enum SettingsTab: Hashable {
        case general
        case projection
        case security
    }
    
    let scope: SessionSettingsScope
    let contactId: UUID?

    @Binding
    var sessionSettings: SessionSettings
    
    @State
    private var selectedTab: SettingsTab = .general

    init(
        scope: SessionSettingsScope = .global,
        sessionSettings: Binding<SessionSettings>,
        contactId: UUID? = nil
    ) {
        self.scope = scope
        self._sessionSettings = sessionSettings
        self.contactId = contactId
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
            ProjectionSessionSettingsTab(sessionSettings: $sessionSettings, scope: scope)
                .tabItem {
                    Text("프로젝션")
                }
                .tag(SettingsTab.projection)
                .id(SettingsTab.projection)
            SecuritySessionSettingsTab(
                sessionSettings: $sessionSettings,
                scope: scope,
                contactId: contactId
            )
                .tabItem {
                    Text("보안")
                }
                .tag(SettingsTab.security)
                .id(SettingsTab.security)
 
        }
        .tabViewStyle(.sidebarAdaptable)
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
    SessionSettingsSheet(
        sessionSettings: .constant(SessionSettings(scope: .global))
    )
        .frame(minHeight: 720)
}
