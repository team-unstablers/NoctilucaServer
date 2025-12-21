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
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("자격 증명 목록")
                Text(scope == .global ? "글로벌 자격 증명은 모든 호스트에 대해 자동으로 사용됩니다." : "선택된 호스트에 대한 자격 증명을 구성합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !canManageEntries {
                Text("연락처가 선택되지 않아 자격 증명을 관리할 수 없습니다.")
                    .foregroundStyle(.secondary)
            } else {
                credentialsListBody
            }

            HStack {
                Spacer()
#if os(macOS)
                Button("삭제", role: .destructive) {
                    removeSelected()
                }
                .disabled(selection.isEmpty)
#endif
                Button("추가") {
                    isAddSheetPresented = true
                }
                .disabled(!canManageEntries)
            }
        }
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
        .sheet(isPresented: $isAddSheetPresented) {
            CredentialAddSheet(scope: scope) { entry in
                entries.append(entry)
            }
        }
    }

    @ViewBuilder
    private var credentialsListBody: some View {
#if os(macOS)
        List(selection: $selection) {
            if entries.isEmpty {
                VStack(alignment: .leading) {
                    Text("(구성된 자격 증명이 없습니다)")
                        .font(.headline)
                    Text("추가 버튼을 눌러 자격 증명을 등록하세요.")
                        .font(.subheadline.monospaced())
                        .lineLimit(1)
                }
                .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    CredentialEntryRow(entry: entry)
                        .tag(entry.id)
                        .focusable(true)
                }
                .onMove(perform: moveEntries)
            }
        }
        .listStyle(.inset)
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
#else
        VStack(alignment: .leading, spacing: 8) {
            if entries.isEmpty {
                Text("(구성된 자격 증명이 없습니다)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        CredentialEntryRow(entry: entry)
                        Spacer()
                        Button(role: .destructive) {
                            remove(entry)
                        } label: {
                            Image(systemName: "trash")
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
#endif
    }

    private func moveEntries(from source: IndexSet, to destination: Int) {
        entries.move(fromOffsets: source, toOffset: destination)
    }

    private func removeSelected() {
        guard !selection.isEmpty else { return }
        entries.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }

    private func remove(_ entry: ClientAuthEntry) {
        entries.removeAll { $0.id == entry.id }
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
