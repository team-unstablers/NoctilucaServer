//
//  FSAllowedEntryEditSheet.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 5/4/26.
//

import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct FSAllowedEntryEditSheet: View {
    enum Mode {
        case add
        case edit
    }

    let mode: Mode
    let onComplete: (SessionSettings.FSAllowedEntry) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State
    private var entryId: UUID

    @State
    private var name: String

    @State
    private var path: String

    @State
    private var acl: SessionSettings.FSAccessACL

    init(
        mode: Mode = .add,
        entry: SessionSettings.FSAllowedEntry? = nil,
        onComplete: @escaping (SessionSettings.FSAllowedEntry) -> Void
    ) {
        self.mode = mode
        self.onComplete = onComplete

        _entryId = State(initialValue: entry?.id ?? UUID())
        _name = State(initialValue: entry?.name ?? "")
        _path = State(initialValue: entry?.path ?? "")
        _acl = State(initialValue: entry?.acl ?? .readOnly)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(markdown: title)
                    .font(.title2.bold())
                Text(markdown: descriptionText)
                    .foregroundStyle(.secondary)
            }

            Form {
                LabeledContent(String(localized: "session-settings.transfer.fs_access.edit.display_name", defaultValue: "표시명")) {
                    TextField(String(localized: "session-settings.transfer.fs_access.edit.display_name.placeholder", defaultValue: "예: 내 작업물"), text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent(String(localized: "session-settings.transfer.fs_access.edit.path", defaultValue: "경로")) {
                    HStack(spacing: 8) {
                        TextField(String(localized: "session-settings.transfer.fs_access.edit.path.placeholder", defaultValue: "/Users/..."), text: $path)
                            .textFieldStyle(.roundedBorder)
#if os(macOS)
                        Button(String(localized: "session-settings.transfer.fs_access.edit.browse", defaultValue: "찾아보기...")) {
                            Task { await selectDirectory() }
                        }
#endif
                    }
                }

                LabeledContent(String(localized: "session-settings.transfer.fs_access.edit.acl", defaultValue: "권한")) {
                    Picker("", selection: $acl) {
                        Text(String(localized: "session-settings.transfer.fs_access.acl.read_only", defaultValue: "읽기 전용"))
                            .tag(SessionSettings.FSAccessACL.readOnly)
                        Text(String(localized: "session-settings.transfer.fs_access.acl.read_write", defaultValue: "읽기/쓰기"))
                            .tag(SessionSettings.FSAccessACL.readWrite)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .formStyle(.grouped)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button(String(localized: "common.cancel", defaultValue: "취소")) {
                    dismiss()
                }
                Button(commitLabel) {
                    handleCommit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCommit)
            }
        }
        .padding()
#if os(macOS)
        .frame(minWidth: 520, minHeight: 320, alignment: .topLeading)
#endif
    }

    private var title: String {
        switch mode {
        case .add:
            return String(localized: "session-settings.transfer.fs_access.edit.title.add", defaultValue: "허용된 디렉토리 추가")
        case .edit:
            return String(localized: "session-settings.transfer.fs_access.edit.title.edit", defaultValue: "허용된 디렉토리 편집")
        }
    }

    private var descriptionText: String {
        String(localized: "session-settings.transfer.fs_access.edit.description", defaultValue: "서버에 노출할 디렉토리를 지정하세요. 표시명은 서버에서 보이는 가상 경로 이름입니다.")
    }

    private var commitLabel: String {
        switch mode {
        case .add:
            return String(localized: "common.add", defaultValue: "추가")
        case .edit:
            return String(localized: "common.save", defaultValue: "저장")
        }
    }

    private var canCommit: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmedName.isEmpty && !trimmedPath.isEmpty
    }

    private func handleCommit() {
        guard canCommit else { return }

        let entry = SessionSettings.FSAllowedEntry(
            id: entryId,
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            path: path.trimmingCharacters(in: .whitespacesAndNewlines),
            acl: acl
        )
        onComplete(entry)
        dismiss()
    }

#if os(macOS)
    @MainActor
    private func selectDirectory() async {
        let panel = NSOpenPanel()
        panel.title = String(localized: "session-settings.transfer.fs_access.edit.panel_title", defaultValue: "공유할 디렉토리 선택")
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false

        if !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            panel.directoryURL = URL(fileURLWithPath: path)
        }

        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow {
            response = await panel.beginSheetModal(for: window)
        } else {
            response = await panel.begin()
        }

        guard response == .OK, let url = panel.url else {
            return
        }

        path = url.path
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = url.lastPathComponent
        }
    }
#endif
}

#Preview("Add") {
    FSAllowedEntryEditSheet(mode: .add) { _ in }
}

#Preview("Edit") {
    FSAllowedEntryEditSheet(
        mode: .edit,
        entry: .init(name: "내 작업물", path: "/Users/cheesekun/Documents/Work", acl: .readWrite)
    ) { _ in }
}
