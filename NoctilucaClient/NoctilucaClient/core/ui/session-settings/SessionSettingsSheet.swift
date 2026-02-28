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
        case input
        case security
    }
    
    enum Action {
        case cancel
        case delete
        case save
        case connect
        case saveAndConnect
    }
    
    let scope: SessionSettingsScope
    let contactId: UUID?
    
    let actionHandler: (Action) -> Void

    @Binding
    var sessionSettings: SessionSettings
    
    @State
    private var selectedTab: SettingsTab = .general
    
    @State
    private var shouldPresentDeleteContactConfirmation: Bool = false

    init(
        scope: SessionSettingsScope = .global,
        sessionSettings: Binding<SessionSettings>,
        contactId: UUID? = nil,
        actionHandler: @escaping (Action) -> Void = { _ in }
    ) {
        self.scope = scope
        self._sessionSettings = sessionSettings
        self.contactId = contactId
        self._selectedTab = State(initialValue: scope == .session ? .general : .projection)
        
        self.actionHandler = actionHandler
    }
    
    @ViewBuilder
    var _body: some View {
        TabView(selection: $selectedTab) {
            if scope == .session {
                GeneralSessionSettingsTab(sessionSettings: $sessionSettings)
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text(markdown: String(localized: "session-settings.tabs.general", defaultValue: "일반"))
                    }
                    .tag(SettingsTab.general)
                    .id(SettingsTab.general)
            }
            
            ProjectionSessionSettingsTab(projection: $sessionSettings.projection, scope: scope)
                .tabItem {
                    Image(systemName: "display")
                    Text(markdown: String(localized: "session-settings.tabs.projection", defaultValue: "프로젝션"))
                }
                .tag(SettingsTab.projection)
                .id(SettingsTab.projection)
            
            InputSessionSettingsTab(sessionSettings: $sessionSettings, scope: scope)
                .tabItem {
                    Image(systemName: "keyboard.fill")
                    Text(markdown: String(localized: "session-settings.tabs.input", defaultValue: "입력"))
                }
                .tag(SettingsTab.input)
                .id(SettingsTab.input)
            
            SecuritySessionSettingsTab(
                sessionSettings: $sessionSettings,
                scope: scope,
                contactId: contactId
            )
                .tabItem {
                    Image(systemName: "lock.fill")
                    Text(markdown: String(localized: "session-settings.tabs.security", defaultValue: "보안"))
                }
                .tag(SettingsTab.security)
                .id(SettingsTab.security)
 
        }
#if os(macOS)
        .tabViewStyle(.sidebarAdaptable)
#endif
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
            .alert(String(localized: "session-settings.delete_contact.title", defaultValue: "연락처 삭제"), isPresented: $shouldPresentDeleteContactConfirmation) {
                Button(String(localized: "common.delete", defaultValue: "삭제"), role: .destructive) {
                    self.actionHandler(.delete)
                }
                Button(String(localized: "common.cancel", defaultValue: "취소"), role: .cancel) {
                    shouldPresentDeleteContactConfirmation = false
                }
            } message: {
                Text(markdown: String(localized: "session-settings.delete_contact.message", defaultValue: "이 연락처를 삭제하면 복구할 수 없습니다."))
            }
    }
    
    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
#if os(iOS)
        ToolbarItemGroup(placement: .topBarLeading) {
            Button(role: .cancel) {
                self.actionHandler(.cancel)
            } label: {
                Image(systemName: "xmark")
            }
        }
        
        ToolbarItemGroup(placement: .topBarTrailing) {
            if scope == .session && contactId == nil {
                Menu {
                    Button(String(localized: "common.connect", defaultValue: "연결하기")) {
                        self.actionHandler(.connect)
                    }
                    Button(String(localized: "session-settings.save_and_connect", defaultValue: "연락처에 저장 후 연결하기")) {
                        self.actionHandler(.saveAndConnect)
                    }
                } label: {
                    Image(systemName: "checkmark")
                }
            } else {
                if scope == .session {
                    Button(role: .destructive) {
                        shouldPresentDeleteContactConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                }

                Button(role: .compatibleConfirm) {
                    self.actionHandler(.save)
                } label: {
                    Image(systemName: "checkmark")
                }
            }
        }
#else
        if scope == .session {
                ToolbarItemGroup(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        shouldPresentDeleteContactConfirmation = true
                    } label: {
                        Text(markdown: String(localized: "common.delete", defaultValue: "삭제"))
                    }
                }
            }

        if scope == .session && contactId == nil {
            ToolbarItemGroup(placement: .cancellationAction) {
                Button(String(localized: "session-settings.save_and_connect.short", defaultValue: "저장 후 연결")) {
                    self.actionHandler(.saveAndConnect)
                }
            }
            
            
            ToolbarItemGroup(placement: .confirmationAction) {
                Button(role: .compatibleConfirm) {
                    self.actionHandler(.connect)
                } label: {
                    Text(markdown: String(localized: "common.connect", defaultValue: "연결"))
                }
            }
        } else {
            ToolbarItemGroup(placement: .cancellationAction) {
                Button(role: .cancel) {
                    self.actionHandler(.cancel)
                } label: {
                    Text(markdown: String(localized: "common.cancel", defaultValue: "취소"))
                }
            }
            
            ToolbarItemGroup(placement: .confirmationAction) {
                Button(role: .compatibleConfirm) {
                    self.actionHandler(.save)
                } label: {
                    Text(markdown: String(localized: "common.save", defaultValue: "저장"))
                }
            }
        }
#endif
    }
    
#if os(macOS)
    var body: some View {
        content
    }
#else
    var body: some View {
        NavigationStack {
            content
                .navigationTitle(String(localized: "session-settings.title", defaultValue: "세션 설정"))
                .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(true)
    }
#endif
}

#Preview {
    SessionSettingsSheet(
        sessionSettings: .constant(SessionSettings(scope: .global))
    )
        .frame(minHeight: 720)
}
