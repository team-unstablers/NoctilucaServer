//
//  ClientSessionListView.swift
//  NoctilucaServer
//
//  Created by Claude on 2/16/26.
//

import SwiftUI
import Combine

// MARK: - Display Model

struct ClientSessionInfo: Identifiable, Hashable {
    let id: UUID
    let agentName: String
    let remoteAddress: String
    let phase: NoctilucaClientSessionPhase

    var phaseDisplayText: String {
        switch phase {
        case .initial:
            return String(localized: "menu.session.phase.initial", defaultValue: "접속 중...")
        case .awaitingAuthentication:
            return String(localized: "menu.session.phase.awaiting_auth", defaultValue: "인증 대기 중")
        case .ready:
            return String(localized: "menu.session.phase.ready", defaultValue: "연결됨")
        case .panic:
            return String(localized: "menu.session.phase.panic", defaultValue: "오류")
        case .closed:
            return String(localized: "menu.session.phase.closed", defaultValue: "종료됨")
        }
    }

    var phaseColor: Color {
        switch phase {
        case .ready:   return .green
        case .panic:   return .red
        default:       return .secondary
        }
    }
}

// MARK: - ViewModel

class ClientSessionListViewModel: ObservableObject {
    @Published var sessions: [ClientSessionInfo] = []
    @Published var selection: Set<UUID> = []

    private var cancellables: Set<AnyCancellable> = []

    var disconnectHandler: ((_ sessionIDs: Set<UUID>) -> Void)?

    func bind(to server: NoctilucaServer) {
        server.$clients
            .receive(on: DispatchQueue.main)
            .sink { [weak self] clients in
                self?.updateSessions(from: clients)
            }
            .store(in: &cancellables)
    }

    func refresh(from server: NoctilucaServer) {
        updateSessions(from: server.clients)
    }

    func disconnectSelected() {
        guard !selection.isEmpty else { return }
        disconnectHandler?(selection)
    }

    func disconnectAll() {
        let allIDs = Set(sessions.map(\.id))
        guard !allIDs.isEmpty else { return }
        disconnectHandler?(allIDs)
    }

    private func updateSessions(from clients: [UUID: NoctilucaClientSession]) {
        sessions = clients.values.map { session in
            ClientSessionInfo(
                id: session.id,
                agentName: session.clientInfo?.agentName
                    ?? String(localized: "menu.session.unknown_agent", defaultValue: "(알 수 없음)"),
                remoteAddress: session.remoteAddress,
                phase: session.phase
            )
        }
        .sorted { $0.agentName < $1.agentName }

        let validIDs = Set(sessions.map(\.id))
        selection = selection.intersection(validIDs)
    }
}

// MARK: - View

struct ClientSessionListView: View {
    @ObservedObject var viewModel: ClientSessionListViewModel

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.sessions.isEmpty {
                emptyStateView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                sessionListView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding()
        .frame(width: 300, height: 300)
    }

    private var emptyStateView: some View {
        Text(String(localized: "menu.session.empty", defaultValue: "접속된 사용자 없음"))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }

    private var sessionListView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(viewModel.sessions) { session in
                        ClientSessionRowView(
                            session: session,
                            isSelected: viewModel.selection.contains(session.id)
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            toggleSelection(session.id)
                        }
                        
                        if session.id != viewModel.sessions.last?.id {
                            Divider()
                                .padding(.horizontal, 8)
                        }
                    }
                }
            }
            
            Divider()
                .padding(.top, 8)
            
            HStack {
                Button(role: .destructive) {
                    viewModel.disconnectSelected()
                } label: {
                    Text(String(localized: "menu.session.disconnect", defaultValue: "접속 끊기"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selection.isEmpty)
                
                Button(role: .destructive) {
                    viewModel.disconnectAll()
                } label: {
                    Text(String(localized: "menu.session.disconnect_all", defaultValue: "전부 접속 끊기"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.sessions.isEmpty)
            }
            .padding(8)
        }
    }

    private func toggleSelection(_ id: UUID) {
        if viewModel.selection.contains(id) {
            viewModel.selection.remove(id)
        } else {
            viewModel.selection.insert(id)
        }
    }
}

// MARK: - Row View

struct ClientSessionRowView: View {
    let session: ClientSessionInfo
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(session.phaseColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.remoteAddress)
                    .font(.system(.body))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(session.agentName)
                    Text("·")
                    Text(session.phaseDisplayText)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(4)
    }
}
