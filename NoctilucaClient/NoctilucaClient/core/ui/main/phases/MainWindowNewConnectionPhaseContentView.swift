//
//  MainWindowNewConnectionPhaseContentView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import SwiftUI

struct MainWindowNewConnectionPhaseContentView: View {
    @EnvironmentObject
    var viewModel: SessionWindowViewModel

    @EnvironmentObject
    var contactSheetCoordinator: ContactSheetCoordinator

    @ObservedObject
    private var contactsStore = ContactsStore.shared

    @ObservedObject
    private var recentStore = RecentConnectionStore.shared

    @State
    private var contactToDelete: ContactItem? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // MARK: - 중앙 로고 + 타이틀
                VStack(spacing: 4) {
#if os(macOS)
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 128, height: 128)
#else
                    if let icon = NoctilucaMeta.applicationIcon() {
                        Image(uiImage: icon)
                            .resizable()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.15), radius: 16)
                            .padding(.bottom, 8)
                    }
#endif

                    HStack(spacing: 0) {
                        Text("Noctiluca ")
                            .font(.largeTitle)
                            .fontWeight(.bold)

                        Text("Navigator")
                            .font(.largeTitle)
                            .fontWeight(.light)
                    }

                    HStack(spacing: 0) {
                        Text(String(format: String(localized: "main.new_connection.version_format", defaultValue: "버전 %@"), NoctilucaMeta.version))
                        
#if UNLEASHED_EDITION
                        Text(" (Unleashed Edition)")
#endif
                        
                    }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 40)

                // MARK: - 최근 연결 섹션
                /*
                if !recentStore.records.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("최근 연결")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 12) {
                                ForEach(recentStore.records.prefix(5)) { record in
                                    RecentConnectionItemView(record: record) {
                                        Task { @MainActor in
                                            do {
                                                try await viewModel.startSession(
                                                    endpoint: .quickConnect(endpointURL: record.endpointURL)
                                                )
                                            } catch {
                                                viewModel.presentConnectionError(error)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                        }
                        .scrollClipDisabled()
                    }
                    .padding(.horizontal, 24)
                }
                 */

                // MARK: - 저장된 호스트 섹션
                VStack(alignment: .leading, spacing: 12) {
                    Text(markdown: String(localized: "main.new_connection.saved_hosts", defaultValue: "저장된 호스트"))
                        .font(.title3)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if contactsStore.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    } else if let loadError = contactsStore.loadError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(markdown: String(localized: "main.new_connection.load_error", defaultValue: "연락처 목록을 불러오지 못했습니다."))
                                .font(.headline)
                            Text(loadError)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 16)
                    } else if contactsStore.contacts.isEmpty {
                        VStack(spacing: 16) {
                            Text(markdown: String(localized: "main.new_connection.no_saved_hosts", defaultValue: "저장된 호스트가 없습니다"))
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text(markdown: String(localized: "main.new_connection.no_saved_hosts_hint", defaultValue: "아래 버튼을 눌러 새 호스트를 추가하거나,\n상단 주소창에서 바로 연결하세요."))
                                .font(.subheadline)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)

                            AddContactTileView {
                                contactSheetCoordinator.presentContactEditor(for: nil)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 24)],
                            spacing: 24
                        ) {
                            ForEach(contactsStore.contacts) { item in
                                ContactItemView(item: item) { action in
                                    handleContactAction(action, for: item)
                                }
                            }

                            AddContactTileView {
                                contactSheetCoordinator.presentContactEditor(for: nil)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert(String(localized: "main.new_connection.delete_host_title", defaultValue: "호스트 삭제"), isPresented: Binding(
            get: { contactToDelete != nil },
            set: { if !$0 { contactToDelete = nil } }
        )) {
            Button(String(localized: "common.cancel", defaultValue: "취소"), role: .cancel) {
                contactToDelete = nil
            }
            Button(String(localized: "common.delete", defaultValue: "삭제"), role: .destructive) {
                if let contact = contactToDelete {
                    try? ContactsStore.shared.remove(id: contact.id)
                    contactToDelete = nil
                }
            }
        } message: {
            if let contact = contactToDelete {
                Text(String(format: String(localized: "main.new_connection.delete_confirm_format", defaultValue: "'%@'을(를) 삭제하시겠습니까?"), contact.displayName))
            }
        }
    }

    private func handleContactAction(_ action: ContactItemAction, for item: ContactItem) {
        switch action {
        case .launch:
            Task { @MainActor in
                do {
                    try await viewModel.startSession(endpoint: .contact(item: item))
                } catch {
                    viewModel.presentConnectionError(error)
                }
            }
        case .edit:
            contactSheetCoordinator.presentContactEditor(for: item)
        case .delete:
            contactToDelete = item
        case .duplicate:
            var duplicated = ContactItem(
                name: String(format: String(localized: "main.new_connection.duplicate_name_format", defaultValue: "%@ (복사본)"), item.displayName),
                endpointURL: item.endpointURL,
                preset: item.settings
            )
            duplicated.settings.credentials.keychainKey = nil
            duplicated.settings.ensureCredentialsKey(scope: .session, contactId: duplicated.id)
            try? ContactsStore.shared.save(duplicated)
        }
    }
}

#Preview("NewConnectionPhase") {
    let viewModel = SessionWindowViewModel()

    MainWindowNewConnectionPhaseContentView()
        .environmentObject(viewModel)
        .environmentObject(viewModel.contactSheetCoordinator)
        .environmentObject(SettingsStore.shared)
        .frame(minWidth: 640, minHeight: 480)
}
