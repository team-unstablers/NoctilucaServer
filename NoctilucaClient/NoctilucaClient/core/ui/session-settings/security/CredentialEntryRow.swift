//
//  CredentialEntryRow.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import SwiftUI

struct CredentialEntryRow: View {
    let entry: ClientAuthEntry

    private var titleText: String {
        let displayName = entry.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !displayName.isEmpty {
            return displayName
        }
        return methodTypeLabel
    }

    private var methodTypeLabel: String {
        switch entry.method {
        case .password:
            return String(localized: "auth.method.password", defaultValue: "사용자명-비밀번호 인증")
        case .simplePassword:
            return String(localized: "auth.method.simple_password", defaultValue: "간단 비밀번호 인증")
        case .sshKey:
            return String(localized: "auth.method.ssh_key", defaultValue: "SSH 키 인증")
        default:
            return String(format: String(localized: "auth.method.external", defaultValue: "외부 인증 방법 (%@)"), entry.method.rawValue)
        }
    }

    private var descriptionText: String {
        var components: [String] = []

        let displayName = entry.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !displayName.isEmpty {
            components.append(methodTypeLabel)
        }

        switch entry.payload {
        case .password(let username, _):
            let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                components.append(String(format: String(localized: "auth.detail.username_format", defaultValue: "사용자명: %@"), trimmed))
            }
        case .simplePassword:
            components.append(String(localized: "auth.detail.password_based", defaultValue: "비밀번호 기반 인증"))
        case .sshKey(let publicKey, _):
            let trimmed = publicKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                components.append(String(format: String(localized: "auth.detail.public_key_format", defaultValue: "공개키: %@"), shortKey(trimmed)))
            }
        }

        if components.isEmpty {
            return String(localized: "auth.detail.no_details", defaultValue: "세부 정보가 없습니다.")
        }

        return components.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(titleText)
                .font(.headline)
            Text(descriptionText)
                .font(.subheadline.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func shortKey(_ value: String) -> String {
        if value.count <= 28 {
            return value
        }
        let prefix = value.prefix(16)
        let suffix = value.suffix(8)
        return "\(prefix)…\(suffix)"
    }
}

#Preview {
    VStack(alignment: .leading) {
        CredentialEntryRow(
            entry: ClientAuthEntry(
                method: .password,
                displayName: "개발용 계정",
                payload: .password(username: "tester", password: "secret")
            )
        )
        CredentialEntryRow(
            entry: ClientAuthEntry(
                method: .sshKey,
                displayName: nil,
                payload: .sshKey(publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINGHpezMcBEmby7zNaxPmj4cFPZ/P6zi3wcO5xC1LPZz", privateKey: Data())
            )
        )
    }
    .padding()
}
