//
//  MainWindowNewConnectionPhaseContentView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import SwiftUI

struct MainWindowNewConnectionPhaseContentView: View {
    @EnvironmentObject
    var viewModel: MainWindowViewModel
    
    @EnvironmentObject
    var contactSheetCoordinator: ContactSheetCoordinator

    @ObservedObject
    private var contactsStore = ContactsStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Text("Noctiluca ")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Navigator")
                        .font(.largeTitle)
                        .fontWeight(.light)

                    Spacer()
                }
                .frame(maxWidth: .infinity)

                Text("버전 \(NoctilucaMeta.version)")
            }
            .padding(.top, 24)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)

            Text("저장된 호스트 목록")
                .font(.title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)

            ScrollView {
                VStack {
                    if contactsStore.isLoading {
                        ProgressView()
                            .padding(.vertical, 32)
                    } else if let loadError = contactsStore.loadError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("연락처 목록을 불러오지 못했습니다.")
                                .font(.headline)
                            Text(loadError)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 16)
                    } else if contactsStore.contacts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("(저장된 호스트가 없습니다)")
                                .font(.headline)
                            Text("우측 상단의 주소창에서 연결할 호스트를 입력하거나 연락처를 추가하세요.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 16)
                    } else {
                        ForEach(contactsStore.contacts) { item in
                            ContactItemView(item: item) { action in
                                switch action {
                                case .launch:
                                    Task {
                                        try? await viewModel.startSession(endpoint: .contact(item: item))
                                    }
                                case .edit:
                                    contactSheetCoordinator.presentContactEditor(for: item)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("NewConnectionPhase") {
    let viewModel = MainWindowViewModel()

    /*
    MainWindowContentView(viewModel: viewModel)
     */

    MainWindowNewConnectionPhaseContentView()
        .environmentObject(viewModel)
        .environmentObject(SettingsStore.shared)
        .frame(minWidth: 640, minHeight: 480)
}
