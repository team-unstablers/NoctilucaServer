//
//  CredentialAddSheet.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import SwiftUI
import Xuanxue

struct CredentialAddSheet: View {
    let scope: SessionSettingsScope
    let handler: (ClientAuthEntry) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State
    private var selectedTemplate: TemplateKind

    @State
    private var displayName: String = ""

    @State
    private var username: String = ""

    @State
    private var password: String = ""

    @State
    private var simplePassword: String = ""

    @State
    private var privateKey: String = ""

    init(scope: SessionSettingsScope, handler: @escaping (ClientAuthEntry) -> Void) {
        self.scope = scope
        self.handler = handler
        self._selectedTemplate = State(initialValue: TemplateKind.available(for: scope).first ?? .sshKey)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading) {
                Text(markdown: String(localized: "session-settings.security.credential_add.title", defaultValue: "자격 증명 추가"))
                    .font(.title2.bold())
                Text(markdown: String(localized: "session-settings.security.credential_add.description", defaultValue: "추가할 자격 증명 유형을 선택하세요."))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(TemplateKind.available(for: scope)) { template in
                    Button {
                        selectedTemplate = template
                    } label: {
                        CredentialTemplateRow(template: template, isSelected: selectedTemplate == template)
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                TextField(String(localized: "session-settings.security.credential_add.display_name_placeholder", defaultValue: "표시 이름 (선택 사항)"), text: $displayName)
                    .textFieldStyle(.roundedBorder)

                templateDetailInputs
            }

            Spacer()

            HStack {
                Spacer()
                Button(String(localized: "common.cancel", defaultValue: "취소")) {
                    dismiss()
                }
                Button(String(localized: "common.add", defaultValue: "추가")) {
                    handleSubmit()
                }
                .disabled(!canCommitSelection)
            }
        }
        .padding()
#if os(macOS)
        .frame(minWidth: 520, minHeight: 420, alignment: .topLeading)
#endif
    }

    private var canCommitSelection: Bool {
        switch selectedTemplate {
        case .password:
            return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .simplePassword:
            return !simplePassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .sshKey:
            return !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    @ViewBuilder
    private var templateDetailInputs: some View {
        switch selectedTemplate {
        case .password:
            VStack(alignment: .leading, spacing: 8) {
                Text(markdown: String(localized: "session-settings.security.credential_add.password.header", defaultValue: "사용자명-비밀번호"))
                    .font(.headline)
                TextField(String(localized: "session-settings.security.credential_add.password.username", defaultValue: "사용자명"), text: $username)
                    .textFieldStyle(.roundedBorder)
                SecureField(String(localized: "session-settings.security.credential_add.password.password", defaultValue: "비밀번호"), text: $password)
                    .textFieldStyle(.roundedBorder)
            }
        case .simplePassword:
            VStack(alignment: .leading, spacing: 8) {
                Text(markdown: String(localized: "session-settings.security.credential_add.simple_password.header", defaultValue: "간단 비밀번호"))
                    .font(.headline)
                SecureField(String(localized: "session-settings.security.credential_add.simple_password.password", defaultValue: "비밀번호"), text: $simplePassword)
                    .textFieldStyle(.roundedBorder)
            }
        case .sshKey:
            VStack(alignment: .leading, spacing: 8) {
                Text(markdown: String(localized: "session-settings.security.credential_add.ssh_key.header", defaultValue: "SSH 키"))
                    .font(.headline)
                TextField(String(localized: "session-settings.security.credential_add.ssh_key.private_key_placeholder", defaultValue: "개인 키 (OpenSSH 형식 / PEM 형식을 지원합니다)"), text: $privateKey, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(3...6)
            }
        }
    }

    private func handleSubmit() {
        guard canCommitSelection else { return }

        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name: String? = trimmedDisplayName.isEmpty ? nil : trimmedDisplayName

        switch selectedTemplate {
        case .password:
            let entry = ClientAuthEntry(
                method: .password,
                displayName: name,
                payload: .password(
                    username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
            )
            handler(entry)
        case .simplePassword:
            let entry = ClientAuthEntry(
                method: .simplePassword,
                displayName: name,
                payload: .simplePassword(password: simplePassword)
            )
            handler(entry)
        case .sshKey:
            let trimmedPrivateKey = privateKey.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // FIXME: 오류 핸들링 및 다이얼로그 표시
            guard let privateKey = try? SSHPrivateKey(sshString: trimmedPrivateKey) else {
                return
            }
            
            let entry = ClientAuthEntry(
                method: .sshKey,
                displayName: name,
                payload: .sshKey(
                    publicKey: "",
                    privateKey: Data(trimmedPrivateKey.utf8)
                )
            )
            handler(entry)
        }

        dismiss()
    }
}

private struct CredentialTemplateRow: View {
    let template: CredentialAddSheet.TemplateKind
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(template.title)
                    .font(.headline)
                Text(template.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

extension CredentialAddSheet {
    enum TemplateKind: String, Identifiable {
        case password
        case simplePassword
        case sshKey

        var id: String { rawValue }

        static func available(for scope: SessionSettingsScope) -> [TemplateKind] {
            switch scope {
            case .global:
                return [.sshKey]
            case .session:
                return [.password, .simplePassword, .sshKey]
            }
        }

        var title: String {
            switch self {
            case .password:
                return String(localized: "session-settings.security.credential_add.template.password.title", defaultValue: "사용자명-비밀번호 인증")
            case .simplePassword:
                return String(localized: "session-settings.security.credential_add.template.simple_password.title", defaultValue: "간단 비밀번호 인증")
            case .sshKey:
                return String(localized: "session-settings.security.credential_add.template.ssh_key.title", defaultValue: "SSH 키 인증")
            }
        }

        var description: String {
            switch self {
            case .password:
                return String(localized: "session-settings.security.credential_add.template.password.description", defaultValue: "사용자명과 비밀번호를 사용한 인증을 수행합니다.")
            case .simplePassword:
                return String(localized: "session-settings.security.credential_add.template.simple_password.description", defaultValue: "비밀번호만을 사용한 인증을 수행합니다.")
            case .sshKey:
                return String(localized: "session-settings.security.credential_add.template.ssh_key.description", defaultValue: "SSH 공개 키/개인 키 기반 인증을 수행합니다.")
            }
        }
    }
}

#Preview {
    CredentialAddSheet(scope: .session) { _ in }
}
