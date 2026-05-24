//
//  FSAllowedEntriesListContainer.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 5/4/26.
//

import SwiftUI

#if os(macOS)
struct FSAllowedEntriesListContainer: View {
    @Binding
    var entries: [SessionSettings.FSAllowedEntry]

    @State
    private var selection = Set<UUID>()

    var body: some View {
        EditableList(
            items: $entries,
            id: \.id,
            selection: $selection,
            title: nil,
            description: nil,
            emptyText: String(localized: "session-settings.transfer.fs_access.entries.empty", defaultValue: "(허용된 디렉토리가 없습니다)\n추가 버튼을 눌러 디렉토리를 등록하세요."),
            rowContent: { entry in
                FSAllowedEntryRow(entry: entry)
            },
            addSheet: { onComplete in
                FSAllowedEntryEditSheet(mode: .add) { entry in
                    onComplete(entry)
                }
            },
            editSheet: { entry, onSave in
                FSAllowedEntryEditSheet(mode: .edit, entry: entry) { newEntry in
                    onSave(newEntry)
                }
            }
        )
    }
}

#Preview {
    FSAllowedEntriesListContainer(
        entries: .constant([
            .init(name: "내 작업물", path: "/Users/cheesekun/Documents/Work", acl: .readOnly),
            .init(name: "Downloads", path: "/Users/cheesekun/Downloads", acl: .readWrite),
        ])
    )
    .padding()
    .frame(width: 600, height: 400)
}
#endif
