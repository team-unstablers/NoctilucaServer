//
//  FSAllowedEntryRow.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 5/4/26.
//

import SwiftUI

struct FSAllowedEntryRow: View {
    let entry: SessionSettings.FSAllowedEntry

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name.isEmpty ? String(localized: "session-settings.transfer.fs_access.entry.unnamed", defaultValue: "(이름 없음)") : entry.name)
                    .font(.headline)
                Text(entry.path)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Text(aclLabel)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(aclBadgeColor.opacity(0.15))
                .foregroundStyle(aclBadgeColor)
                .clipShape(Capsule())
        }
#if os(macOS)
        .padding(.vertical, 4)
#endif
    }

    private var iconName: String {
        switch entry.acl {
        case .readOnly:
            return "folder"
        case .readWrite:
            return "folder.badge.gearshape"
        }
    }

    private var aclLabel: String {
        switch entry.acl {
        case .readOnly:
            return String(localized: "session-settings.transfer.fs_access.acl.read_only", defaultValue: "읽기 전용")
        case .readWrite:
            return String(localized: "session-settings.transfer.fs_access.acl.read_write", defaultValue: "읽기/쓰기")
        }
    }

    private var aclBadgeColor: Color {
        switch entry.acl {
        case .readOnly:
            return .secondary
        case .readWrite:
            return .orange
        }
    }
}

#Preview {
    VStack(spacing: 8) {
        FSAllowedEntryRow(
            entry: .init(name: "내 작업물", path: "/Users/cheesekun/Documents/Work", acl: .readOnly)
        )
        FSAllowedEntryRow(
            entry: .init(name: "Downloads", path: "/Users/cheesekun/Downloads", acl: .readWrite)
        )
    }
    .padding()
}
