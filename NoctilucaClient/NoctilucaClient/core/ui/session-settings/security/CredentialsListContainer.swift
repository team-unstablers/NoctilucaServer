//
//  CredentialsListContainer.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import SwiftUI

struct CredentialsListContainer: View {
    @Binding
    var sessionSettings: SessionSettings

    let scope: SessionSettingsScope
    let contactId: UUID?

    @State
    private var entries: [ClientAuthEntry] = []

    @State
    private var selection = Set<UUID>()

    @State
    private var isAddSheetPresented = false

    @State
    private var isLoading = false

    private var canManageEntries: Bool {
        if scope == .global {
            return true
        }
        return contactId != nil
    }

    var body: some View {
#if os(macOS)
        macOSBody
            .onAppear(perform: reloadEntries)
            .onChange(of: scope) { _, _ in
                reloadEntries()
            }
            .onChange(of: contactId) { _, _ in
                reloadEntries()
            }
            .onChange(of: entries) { _, _ in
                guard !isLoading else { return }
                saveEntries()
            }
#else
        iOSBody
            .onAppear(perform: reloadEntries)
            .onChange(of: scope) { _, _ in
                reloadEntries()
            }
            .onChange(of: contactId) { _, _ in
                reloadEntries()
            }
            .onChange(of: entries) { _, _ in
                guard !isLoading else { return }
                saveEntries()
            }
#endif
    }

#if os(macOS)
    @ViewBuilder
    private var macOSBody: some View {
        if !canManageEntries {
            VStack(alignment: .leading, spacing: 12) {
                headerView
                Text(String(localized: "session-settings.security.credentials.no_contact_selected", defaultValue: "연락처가 선택되지 않아 자격 증명을 관리할 수 없습니다."))
                    .foregroundStyle(.secondary)
                Spacer()
            }
        } else {
            EditableList(
                items: $entries,
                id: \.id,
                selection: $selection,
                title: String(localized: "session-settings.security.credentials.title", defaultValue: "자격 증명 목록"),
                description: scope == .global ? String(localized: "session-settings.security.credentials.description.global", defaultValue: "글로벌 자격 증명은 모든 호스트에 대해 자동으로 사용됩니다.") : String(localized: "session-settings.security.credentials.description.session", defaultValue: "선택된 호스트에 대한 자격 증명을 구성합니다."),
                emptyText: String(localized: "session-settings.security.credentials.empty", defaultValue: "(구성된 자격 증명이 없습니다)\n추가 버튼을 눌러 자격 증명을 등록하세요."),
                rowContent: { entry in
                    CredentialEntryRow(entry: entry)
                },
                addSheet: { onComplete in
                    CredentialAddSheet(scope: scope) { entry in
                        onComplete(entry)
                    }
                }
            )
        }
    }
#endif

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "session-settings.security.credentials.title", defaultValue: "자격 증명 목록"))
            Text(scope == .global ? String(localized: "session-settings.security.credentials.description.global", defaultValue: "글로벌 자격 증명은 모든 호스트에 대해 자동으로 사용됩니다.") : String(localized: "session-settings.security.credentials.description.session", defaultValue: "선택된 호스트에 대한 자격 증명을 구성합니다."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var iOSBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
                .padding(.bottom, 12)
            
            Divider()
            
            if !canManageEntries {
                Text(String(localized: "session-settings.security.credentials.no_contact_selected", defaultValue: "연락처가 선택되지 않아 자격 증명을 관리할 수 없습니다."))
                    .foregroundStyle(.secondary)
            } else {
                EditableList(
                    items: $entries,
                    id: \.id,
                    selection: $selection,
                    title: nil,
                    description: nil,
                    emptyText: String(localized: "session-settings.security.credentials.empty", defaultValue: "(구성된 자격 증명이 없습니다)\n추가 버튼을 눌러 자격 증명을 등록하세요."),
                    rowContent: { entry in
                        CredentialEntryRow(entry: entry)
                    },
                    addSheet: { onComplete in
                        CredentialAddSheet(scope: scope) { entry in
                            onComplete(entry)
                        }
                    }
                )
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func reloadEntries() {
        guard canManageEntries else {
            entries = []
            return
        }

        isLoading = true
        ensureCredentialsKey()
        entries = SessionCredentialsStore.load(
            scope: scope,
            contactId: contactId,
            keyOverride: sessionSettings.credentials.keychainKey
        )
        isLoading = false
    }

    private func saveEntries() {
        guard canManageEntries else { return }
        ensureCredentialsKey()
        let ref = SessionCredentialsStore.save(
            entries,
            scope: scope,
            contactId: contactId,
            currentRef: sessionSettings.credentials
        )
        sessionSettings.credentials = ref
    }

    private func ensureCredentialsKey() {
        guard sessionSettings.credentials.keychainKey == nil else { return }
        sessionSettings.ensureCredentialsKey(scope: scope, contactId: contactId)
    }
}

#Preview {
    CredentialsListContainer(
        sessionSettings: .constant(SessionSettings(scope: .global)),
        scope: .global,
        contactId: nil
    )
}
