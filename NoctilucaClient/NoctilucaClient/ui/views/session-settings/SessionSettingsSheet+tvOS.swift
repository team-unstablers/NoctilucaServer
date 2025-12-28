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
        HStack {
            VStack {
                Text("test")
            }
            .frame(maxWidth: .infinity)
            
            Form {
                NavigationLink(destination: {
                    GeneralSessionSettingsTab(sessionSettings: $sessionSettings)
                }, label: {
                    Label("일반", systemImage: "gearshape.fill")
                })
                
                NavigationLink(destination: {
                    ProjectionSessionSettingsTab(sessionSettings: $sessionSettings, scope: scope)
                }, label: {
                    Label("프로젝션", systemImage: "display")
                })
                
                NavigationLink(destination: {
                    InputSessionSettingsTab(sessionSettings: $sessionSettings, scope: scope)
                }, label: {
                    Label("입력", systemImage: "keyboard.fill")
                })
                
                NavigationLink(destination: {
                    SecuritySessionSettingsTab(
                        sessionSettings: $sessionSettings,
                        scope: scope,
                        contactId: contactId
                    )
                }, label: {
                    Label("보안", systemImage: "lock.fill")
                })
            }
            .frame(maxWidth: .infinity)
        }
        /*
        TabView(selection: $selectedTab) {
            if scope == .session {
                GeneralSessionSettingsTab(sessionSettings: $sessionSettings)
                    .tabItem {
                        Image(systemName: "gearshape.fill")
                        Text("일반")
                    }
                    .tag(SettingsTab.general)
                    .id(SettingsTab.general)
            }
            
            ProjectionSessionSettingsTab(sessionSettings: $sessionSettings, scope: scope)
                .tabItem {
                    Image(systemName: "display")
                    Text("프로젝션")
                }
                .tag(SettingsTab.projection)
                .id(SettingsTab.projection)
            
            InputSessionSettingsTab(sessionSettings: $sessionSettings, scope: scope)
                .tabItem {
                    Image(systemName: "keyboard.fill")
                    Text("입력")
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
                    Text("보안")
                }
                .tag(SettingsTab.security)
                .id(SettingsTab.security)
 
        }
#if !os(tvOS)
        .tabViewStyle(.sidebarAdaptable)
#endif
         */
    }

    @ViewBuilder
    private var content: some View {
        _body
#if !os(tvOS)
            .toolbar {
                toolbarItems
            }
#endif
            .alert("연락처 삭제", isPresented: $shouldPresentDeleteContactConfirmation) {
                Button("삭제", role: .destructive) {
                    self.actionHandler(.delete)
                }
                Button("취소", role: .cancel) {
                    shouldPresentDeleteContactConfirmation = false
                }
            } message: {
                Text("이 연락처를 삭제하면 복구할 수 없습니다.")
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
                    Button("연결하기") {
                        self.actionHandler(.connect)
                    }
                    Button("연락처에 저장 후 연결하기") {
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

                Button(role: .confirm) {
                    self.actionHandler(.save)
                } label: {
                    Image(systemName: "checkmark")
                }
            }
        }
#else
        ToolbarItemGroup(placement: .destructiveAction) {
            Button(role: .cancel) {
                self.actionHandler(.cancel)
            } label: {
                Text("취소")
            }
        }
        
        if scope == .session && contactId == nil {
            ToolbarItemGroup(placement: .cancellationAction) {
                Button("저장 후 연결") {
                    self.actionHandler(.saveAndConnect)
                }
            }
            
            
            ToolbarItemGroup(placement: .confirmationAction) {
                Button(role: .confirm) {
                    self.actionHandler(.connect)
                } label: {
                    Text("연결")
                }
            }
        } else {
            if scope == .session {
                ToolbarItemGroup(placement: .cancellationAction) {
                    Button(role: .destructive) {
                        shouldPresentDeleteContactConfirmation = true
                    } label: {
                        Text("삭제")
                    }
                }
            }
            
            ToolbarItemGroup(placement: .confirmationAction) {
                Button(role: .confirm) {
                    self.actionHandler(.save)
                } label: {
                    Text("저장")
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
                .navigationTitle("세션 설정")
#if !os(tvOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
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
