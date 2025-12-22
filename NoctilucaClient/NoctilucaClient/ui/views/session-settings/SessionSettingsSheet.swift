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

    struct Action: Identifiable {
        enum Kind: Int {
            case cancel = 0
            case secondary = 1
            case primary = 2
        }

        let kind: Kind
        let title: String
        let role: ButtonRole?
        let isEnabled: Bool
        let handler: () -> Void

        init(kind: Kind, title: String, role: ButtonRole? = nil, isEnabled: Bool = true, handler: @escaping () -> Void) {
            self.kind = kind
            self.title = title
            self.role = role
            self.isEnabled = isEnabled
            self.handler = handler
        }

        var id: String {
            "\(kind.rawValue)-\(title)"
        }
    }
    
    let scope: SessionSettingsScope
    let contactId: UUID?
    let actions: [Action]

    @Binding
    var sessionSettings: SessionSettings
    
    @State
    private var selectedTab: SettingsTab = .general

    init(
        scope: SessionSettingsScope = .global,
        sessionSettings: Binding<SessionSettings>,
        contactId: UUID? = nil,
        actions: [Action] = []
    ) {
        self.scope = scope
        self._sessionSettings = sessionSettings
        self.contactId = contactId
        self.actions = actions
        self._selectedTab = State(initialValue: scope == .session ? .general : .projection)
    }
    
    @ViewBuilder
    var _body: some View {
        TabView(selection: $selectedTab) {
            if scope == .session {
                GeneralSessionSettingsTab(sessionSettings: $sessionSettings)
                    .tabItem {
                        Text("일반")
                    }
                    .tag(SettingsTab.general)
                    .id(SettingsTab.general)
            }
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

    @ViewBuilder
    private var content: some View {
        _body
#if os(macOS)
            .frame(height: 600)
#endif
            .toolbar {
                toolbarItems
            }
    }
    
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
#if os(iOS)
        #warning("FIXME: 이거 너무 난잡해요 ㅠㅠ")
        ToolbarItemGroup(placement: .topBarLeading) {
            ForEach(actions.filter { $0.kind == .cancel }) { action in
                Button(action.title, role: action.role) {
                    action.handler()
                }
                .disabled(!action.isEnabled)
            }
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                ForEach(actions.filter { $0.kind == .secondary || $0.kind == .primary }.sorted { $0.kind.rawValue < $1.kind.rawValue }) { action in
                    Button(action.title, role: action.role) {
                        action.handler()
                    }
                    .disabled(!action.isEnabled)
                }
            } label: {
                Image(systemName: "checkmark")
            }
        }
#else
        ToolbarItemGroup(placement: .destructiveAction) {
            ForEach(actions.filter { $0.kind == .cancel }) { action in
                Button(action.title, role: action.role) {
                    action.handler()
                }
                .disabled(!action.isEnabled)
            }
        }
        
        ToolbarItemGroup(placement: .cancellationAction) {
            ForEach(actions.filter { $0.kind == .secondary }) { action in
                Button(action.title, role: action.role) {
                    action.handler()
                }
                .disabled(!action.isEnabled)
            }
        }

        
        ToolbarItemGroup(placement: .confirmationAction) {
            ForEach(actions.filter { $0.kind == .primary }) { action in
                Button(action.title, role: action.role) {
                    action.handler()
                }
                .disabled(!action.isEnabled)
            }
        }
#endif
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            ForEach(actions.sorted { $0.kind.rawValue < $1.kind.rawValue }) { action in
                Button(action.title, role: action.role) {
                    action.handler()
                }
                // .buttonStyle(action.kind == .primary ? .borderedProminent : .bordered)
                .disabled(!action.isEnabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }
    
#if os(macOS)
    var body: some View {
        content
    }
#else
    var body: some View {
        NavigationStack {
            content
                .navigationTitle("세션 설정")
                .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(!actions.isEmpty)
    }
#endif
}

#Preview {
    SessionSettingsSheet(
        sessionSettings: .constant(SessionSettings(scope: .global))
    )
        .frame(minHeight: 720)
}
