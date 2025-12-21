//
//  NewConnectionPhaseView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import Foundation

import SwiftUI
import Combine

import AVFoundation

import SiriusKitClient

#if os(macOS)
import AppKit
#endif

struct MainWindowNewConnectionPhaseContentView: View {
    @EnvironmentObject
    var viewModel: MainWindowViewModel

    @EnvironmentObject
    private var settingsStore: SettingsStore

    @State
    private var isContactEditorPresented: Bool = false

    @State
    private var contactDraft: ContactItem = ContactItem(name: nil, endpointURL: "", preset: SessionSettings(scope: .session))

    @State
    private var isEditingContact: Bool = false

    @State
    private var isDeleteConfirmationPresented: Bool = false

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

            HStack {
                Text("저장된 호스트 목록")
                    .font(.title)
                Spacer()
                Button("추가") {
                    presentContactEditor(for: nil)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)

            ScrollView {
                VStack {
                    if viewModel.isLoadingContacts {
                        ProgressView()
                            .padding(.vertical, 32)
                    } else if let contactsLoadError = viewModel.contactsLoadError {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("연락처 목록을 불러오지 못했습니다.")
                                .font(.headline)
                            Text(contactsLoadError)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 16)
                    } else if contacts.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("(저장된 호스트가 없습니다)")
                                .font(.headline)
                            Text("우측 상단의 주소창에서 연결할 호스트를 입력하거나 연락처를 추가하세요.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 16)
                    } else {
                        ForEach(viewModel.contacts) { item in
                            ContactItemView(item: item) { action in
                                switch action {
                                case .launch:
                                    Task {
                                        try? await viewModel.startSession(endpoint: .contact(item: item))
                                    }
                                case .edit:
                                    presentContactEditor(for: item)
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
        .sheet(isPresented: $isContactEditorPresented) {
            SessionSettingsSheet(
                scope: .session,
                sessionSettings: $contactDraft.settings,
                contactId: contactDraft.id,
                actions: [
                    .init(kind: .cancel, title: "취소", role: .cancel) {
                        isContactEditorPresented = false
                    },
                    isEditingContact
                        ? .init(kind: .secondary, title: "삭제", role: .destructive) {
                            isDeleteConfirmationPresented = true
                        }
                        : nil,
                    .init(kind: .primary, title: isEditingContact ? "저장" : "추가") {
                        saveContact()
                    }
                ].compactMap { $0 }
            )
        }
        .alert("연락처 삭제", isPresented: $isDeleteConfirmationPresented) {
            Button("삭제", role: .destructive) {
                deleteContact()
            }
            Button("취소", role: .cancel) {
                isDeleteConfirmationPresented = false
            }
        } message: {
            Text("이 연락처를 삭제하면 복구할 수 없습니다.")
        }
    }

    private func presentContactEditor(for item: ContactItem?) {
        if let item {
            contactDraft = item
            isEditingContact = true
        } else {
            contactDraft = ContactItem(
                name: nil,
                endpointURL: "",
                preset: settingsStore.settings.sessionDefaults
            )
            isEditingContact = false
        }

        isContactEditorPresented = true
    }

    private func saveContact() {
        do {
            try ContactStore.save(contactDraft)
            isContactEditorPresented = false
        } catch {
            print("Failed to save contact: \(error.localizedDescription)")
        }
    }

    private func deleteContact() {
        do {
            try ContactStore.remove(id: contactDraft.id)
            isDeleteConfirmationPresented = false
            isContactEditorPresented = false
        } catch {
            print("Failed to delete contact: \(error.localizedDescription)")
        }
    }
}

struct MainWindowConnectingPhaseContentView: View {
    @EnvironmentObject
    var viewModel: MainWindowViewModel

    @State
    var isLogAreaVisible: Bool = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            VStack(alignment: .leading) {
                
                Spacer()
                
                HStack(spacing: 0) {
                    Text("연결 중")
                        .font(.largeTitle)
                        .fontWeight(.light)
                }
                .padding(.bottom, 2)
                
                Text("\(self.viewModel.endpointURL)에 연결하고 있습니다...")
                    .padding(.bottom, 32)
                
                Spacer()
                
                
                VStack {
                }
                .frame(maxWidth: .infinity)
            }
            
            
                Text(
                    self.viewModel.connectionLog.joined(separator: "\n")
                )
                .font(.system(size: 12).monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
#if os(macOS)
                .overlay {
                    LinearGradient(
                        colors: [
                            Color(NSColor.windowBackgroundColor),
                            Color.clear,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .opacity(isLogAreaVisible ? 0.0 : 1.0)
                }
#endif
                .onHover { hoverState in
                    if hoverState {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLogAreaVisible = true
                        }
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isLogAreaVisible = false
                        }
                    }
                    
                }
        }
        .padding(24)
    }
}

struct MainWindowMainPhaseContentView: View {
    @EnvironmentObject
    var viewModel: MainWindowViewModel
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                if let displayLayer = viewModel.displayLayer {
                    SampleBufferDisplayView(displayLayer: displayLayer)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .scaleEffect(scale)
                        .offset(offset)
                }
                
                if let session = viewModel.client?.projectionChannel?.sessions.first?.value,
                   let codec = session.codec
                {
                    PerformanceOverlay(codec: codec, rtt: viewModel.averagePingRTT)
                        .padding(16)
                }

#if os(macOS)
                if let warning = viewModel.inputWarning {
                    InputWarningBanner(
                        warning: warning,
                        openSettings: {
                            TCCUtil.shared.openSystemPreferences(for: .inputMonitoring)
                        },
                        retry: {
                            TCCUtil.shared.requestAccess(for: .inputMonitoring)
                            viewModel.retryInputRedirection()
                        }
                    )
                    .frame(maxWidth: 420, alignment: .leading)
                    .padding(16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
#endif
                
                Rectangle()
                    .fill(Color.black.opacity(0.001))
                    // .ignoresSafeArea()
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                withAnimation(.spring()) {
                                    // toolbarVisible = false
                                }
                                
                                let delta = value / lastScale
                                lastScale = value
                                scale = min(max(scale * delta, 0.25), 4)
                            }
                            .onEnded { _ in
                                lastScale = 1.0
                                withAnimation(.spring()) {
                                    if scale < 1 {
                                        scale = 1
                                        offset = .zero
                                    }
                                }
                            }
                            .simultaneously(with:
                                                DragGesture()
                                .onChanged { value in
                                    if scale > 1 {
                                        withAnimation(.spring()) {
                                            // toolbarVisible = false
                                        }

                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                    
                                    // 화면 밖으로 나가지 않도록 제한
                                    withAnimation(.spring()) {
                                        let maxX = (geometry.size.width * (scale - 1)) / 2
                                        let maxY = (geometry.size.height * (scale - 1)) / 2
                                        
                                        offset.width = min(max(offset.width, -maxX), maxX)
                                        offset.height = min(max(offset.height, -maxY), maxY)
                                        lastOffset = offset
                                    }
                                }
                                           )
                    )
                    .onTapGesture(count: 1) {
                        withAnimation(.spring()) {
                            // toolbarVisible = !toolbarVisible
                        }
                    }
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            // toolbarVisible = false
                            if scale > 1 {
                                scale = 1
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2
                            }
                        }
                    }
                

            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .if(viewModel.client != nil) {
                $0.onReceive(viewModel.client!.uiEvents) { event in
                    guard case .FIXME_projectionStarted(let projectionSession) = event else {
                        return
                    }
                    
                    viewModel.displayLayer = projectionSession.displayLayer
                }
            }
        }
    }
    
}

#if os(macOS)
private struct InputWarningBanner: View {
    let warning: InputWarning
    let openSettings: () -> Void
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(warning.title)
                .font(.headline)
            Text(warning.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button("설정 열기") {
                    openSettings()
                }
                Button("다시 시도") {
                    retry()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.95))
                .shadow(radius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}
#endif


struct MainWindowContentView: View {
#if os(iOS)
    @Environment(\.horizontalSizeClass)
    var horizontalSizeClass
#endif
    
    @EnvironmentObject
    var viewModel: MainWindowViewModel
    
    var body: some View {
        switch viewModel.phase {
        case .newConnection:
            MainWindowNewConnectionPhaseContentView()
#if os(iOS)
                .safeAreaPadding(.vertical)
                .padding(.top, horizontalSizeClass == .compact ? 0 : 32)
#endif
        case .connecting:
            MainWindowConnectingPhaseContentView()
        case .connected:
            MainWindowMainPhaseContentView()
        default:
            EmptyView()
        }
        
    }
}

#Preview("NewConnectionPhase") {
    let viewModel = MainWindowViewModel()
    
    /*
    MainWindowContentView(viewModel: viewModel)
     */
    
    MainWindowNewConnectionPhaseContentView()
        .environmentObject(viewModel)
        .environmentObject(SettingsStore(loadFromDisk: false))
        .frame(minWidth: 640, minHeight: 480)
}

#Preview("ConnectingPhase") {
    let viewModel = MainWindowViewModel()
    
    MainWindowConnectingPhaseContentView()
        .environmentObject(viewModel)
        .frame(minWidth: 640, minHeight: 480)
}
