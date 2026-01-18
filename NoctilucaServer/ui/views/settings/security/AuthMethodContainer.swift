//
//  AuthMethodContainer.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation
import AppKit
#if canImport(Collaboration)
import Collaboration
#endif
import SwiftUI

import Xuanxue

import NoctilucaPluginKit

struct AuthMethodContainer: View {
    @Binding
    var authMethods: [AuthEntry]
    @State private var selection = Set<AuthEntry>()
    @State private var isAddSheetPresented = false
    
    init(authMethods: Binding<[AuthEntry]>) {
        self._authMethods = authMethods
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(selection: $selection) {
                if authMethods.isEmpty {
                    VStack(alignment: .leading) {
                        Text(String(localized: "settings.security.auth_method.empty_title", defaultValue: "(구성된 인증 방법이 없습니다)"))
                            .font(.headline)
                        Text(String(localized: "settings.security.auth_method.empty_description", defaultValue: "현재 상태로는 아무도 로그인할 수 없습니다. 인증 방법을 추가하려면 아래 '추가' 버튼을 클릭하세요."))
                            .font(.subheadline.monospaced())
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(authMethods, id: \.self) { entry in
                        AuthMethodEntry(entry: entry)
                            .tag(entry.hashValue)
                            .focusable(true)
                    }
                    .onMove(perform: moveAuthMethods)
                }
            }
            .listStyle(.inset)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            
            HStack {
                Spacer()
                Button(String(localized: "settings.security.auth_method.delete", defaultValue: "삭제"), role: .destructive) {
                    removeSelected()
                }
                .disabled(selection.isEmpty)

                Button(String(localized: "settings.security.auth_method.add", defaultValue: "추가")) {
                    isAddSheetPresented = true
                }
            }
        }
        .sheet(isPresented: $isAddSheetPresented) {
            AuthMethodSelectionSheet(isPresented: $isAddSheetPresented) { newMethod in
                guard !authMethods.contains(newMethod) else { return }
                authMethods.append(newMethod)
            }
        }
    }
    
    private func moveAuthMethods(from source: IndexSet, to destination: Int) {
        authMethods.move(fromOffsets: source, toOffset: destination)
    }
    
    private func removeSelected() {
        guard !selection.isEmpty else { return }
        authMethods.removeAll { selection.contains($0) }
        selection.removeAll()
    }
}

private struct AuthMethodSelectionSheet: View {
    @Binding var isPresented: Bool
    var onSelect: (AuthEntry) -> Void
    
    @State
    private var selectedTemplate: TemplateKind = TemplateKind.available.first ?? .pam
    @State
    private var pamAllowMode: PAMAllowMode = .user
    @State
    private var pamPrincipal: String = NSUserName()
    @State 
    private var simplePasswordValue: String = ""
    @State 
    private var sshPublicKey: String = ""
    
    @State
    var shouldPresentErrorAlert: Bool = false
    
    @State
    var error: Error? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "settings.security.auth_method.sheet.title", defaultValue: "인증 방법 선택"))
                .font(.title2.bold())
            Text(String(localized: "settings.security.auth_method.sheet.description", defaultValue: "추가할 인증 방법을 선택하세요."))
                .foregroundStyle(.secondary)
            
            VStack(alignment: .leading, spacing: 8) {
                ForEach(TemplateKind.available) { template in
                    Button {
                        selectedTemplate = template
                    } label: {
                        AuthMethodTemplateRow(template: template, isSelected: selectedTemplate == template)
                    }
                    .focusable(true)
                    .buttonStyle(.plain)
                }
            }
            
            templateDetailInputs
            
            Spacer()
            
            HStack {
                Spacer()
                Button(String(localized: "settings.security.auth_method.sheet.cancel", defaultValue: "취소")) {
                    isPresented = false
                }
                Button(String(localized: "settings.security.auth_method.sheet.add", defaultValue: "추가")) {
                    handleSubmit()
                }
                .disabled(!canCommitSelection)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 420, alignment: .topLeading)
        .alert(isPresented: $shouldPresentErrorAlert) {
            Alert(
                title: Text(String(localized: "settings.security.auth_method.sheet.error_alert.title", defaultValue: "오류 발생")),
                message: Text(error?.localizedDescription ?? String(localized: "settings.security.auth_method.sheet.error_alert.unknown_error", defaultValue: "알 수 없는 오류가 발생했습니다.")),
                dismissButton: .default(Text(String(localized: "settings.security.auth_method.sheet.error_alert.dismiss", defaultValue: "확인")))
            )
        }
    }
    
    private var canCommitSelection: Bool {
        switch selectedTemplate {
        case .pam:
            return !pamPrincipal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .simplePassword:
            return !simplePasswordValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .sshKey:
            return !sshPublicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        #if DEBUG
        case .null:
            return true
        #endif
        }
    }
    
    @ViewBuilder
    private var templateDetailInputs: some View {
        switch selectedTemplate {
        case .pam:
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "settings.security.auth_method.pam.detail_title", defaultValue: "PAM 인증 세부 설정"))
                    .font(.headline)
                Picker(String(localized: "settings.security.auth_method.pam.allow_scope", defaultValue: "허용 범위"), selection: $pamAllowMode) {
                    Text(String(localized: "settings.security.auth_method.pam.user", defaultValue: "사용자")).tag(PAMAllowMode.user)
                    Text(String(localized: "settings.security.auth_method.pam.group", defaultValue: "그룹")).tag(PAMAllowMode.group)
                }
                .pickerStyle(.segmented)
                HStack(spacing: 8) {
                    TextField(pamAllowMode == .user ? String(localized: "settings.security.auth_method.pam.user_placeholder", defaultValue: "허용 사용자 이름") : String(localized: "settings.security.auth_method.pam.group_placeholder", defaultValue: "허용 그룹 이름"), text: $pamPrincipal)
                        .textFieldStyle(.roundedBorder)
                    #if os(macOS) && canImport(Collaboration)
                    Button(String(localized: "settings.security.auth_method.pam.select_identity", defaultValue: "사용자/그룹 선택…")) {
                        presentIdentityPicker()
                    }
                    .focusable(true)
                    #endif
                }
            }
        case .simplePassword:
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "settings.security.auth_method.simple_password.title", defaultValue: "간단 비밀번호 인증"))
                    .font(.headline)
                Text(String(localized: "settings.security.auth_method.simple_password.description", defaultValue: "입력된 비밀번호는 SHA-512 + bcrypt로 이중 해시 처리되어 저장됩니다."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(String(localized: "settings.security.auth_method.simple_password.placeholder", defaultValue: "비밀번호 입력"), text: $simplePasswordValue, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...3)
            }
        case .sshKey:
            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "settings.security.auth_method.ssh_key.title", defaultValue: "SSH 키 인증"))
                    .font(.headline)
                Text(String(localized: "settings.security.auth_method.ssh_key.description", defaultValue: "허용할 공개 키를 입력하세요."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField(String(localized: "settings.security.auth_method.ssh_key.placeholder", defaultValue: "ssh-ed25519 AAAA..."), text: $sshPublicKey, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2...4)
            }
        #if DEBUG
        case .null:
            EmptyView()
        #endif
        }
    }
    
    private func handleSubmit() {
        guard canCommitSelection else { return }
        do {
            let method = try selectedAuthMethod()
            onSelect(method)
            isPresented = false
        } catch {
            self.error = error
            shouldPresentErrorAlert = true
        }
    }
    
    private func selectedAuthMethod() throws -> AuthEntry {
        switch selectedTemplate {
        case .pam:
            let principal = pamPrincipal.trimmingCharacters(in: .whitespacesAndNewlines)
            
            if pamAllowMode == .group {
                return AuthEntry(method: .password, identifier: "group:\(principal)")
            } else if pamAllowMode == .user {
                return AuthEntry(method: .password, identifier: "user:\(principal)")
            } else {
                fatalError("Unhandled PAM allow mode: \(pamAllowMode)")
            }
        case .simplePassword:
            let hash = try! Bcrypt.hash(
                password: try! Bcrypt.sha512(value: simplePasswordValue.data(using: .utf8)!)
            )
            
            return AuthEntry(method: .simplePassword, identifier: "bcrypt+sha512", data: hash)
        case .sshKey:
            let keyString = sshPublicKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = try SSHPublicKey(sshString: keyString)
            
            let comment = key.comment ?? keyString
            
            return AuthEntry(method: .sshKey, identifier: comment, data: keyString.data(using: .utf8))
        #if DEBUG
        case .null:
            return AuthEntry(method: .null, identifier: "")
        #endif
        }
    }
    
    #if os(macOS) && canImport(Collaboration)
    @MainActor
    private func presentIdentityPicker() {
        guard let window = NSApp.keyWindow ?? NSApplication.shared.windows.first else { return }
        let picker = CBIdentityPicker()
        picker.allowsMultipleSelection = false
        picker.title = String(localized: "settings.security.auth_method.pam.picker_title", defaultValue: "인증 허용 대상 선택")
        picker.runModal(for: window) { response in
            guard response == .OK else { return }
            applyPickedIdentity(picker.identities.first)
        }
    }
    
    @MainActor
    private func applyPickedIdentity(_ identity: CBIdentity?) {
        guard let identity else { return }
        if identity is CBGroupIdentity {
            pamAllowMode = .group
        } else {
            pamAllowMode = .user
        }
        
        guard !identity.posixName.isEmpty else {
            return
        }
        
        pamPrincipal = identity.posixName

        /*
        if !identity.posixName.isEmpty {
        } else if !identity.fullName.isEmpty {
            fatalError("FIXME")
            pamPrincipal = identity.fullName
        } else if !identity.uuidString.isEmpty {
            fatalError("FIXME")
            pamPrincipal = identity.uuidString
        }
         */
    }
    #endif
}

private struct AuthMethodTemplateRow: View {
    let template: AuthMethodSelectionSheet.TemplateKind
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
                    // .foregroundStyle(.accentColor)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .focusable(true)
    }
}

private extension AuthMethodSelectionSheet {
    enum TemplateKind: String, Identifiable {
        case pam
        case simplePassword
        case sshKey
        #if DEBUG
        case null
        #endif
        
        var id: String { rawValue }
        
        static var available: [TemplateKind] {
            var values: [TemplateKind] = [.pam, .simplePassword, .sshKey]
            #if DEBUG
            values.append(.null)
            #endif
            return values
        }
        
        var title: String {
            switch self {
            case .pam:
                return String(localized: "settings.security.auth_method.template.pam.title", defaultValue: "UNIX PAM 인증 (사용자명-비밀번호)")
            case .simplePassword:
                return String(localized: "settings.security.auth_method.template.simple_password.title", defaultValue: "간단 비밀번호 인증 (권장하지 않음)")
            case .sshKey:
                return String(localized: "settings.security.auth_method.template.ssh_key.title", defaultValue: "SSH 키 인증")
            #if DEBUG
            case .null:
                return String(localized: "settings.security.auth_method.template.null.title", defaultValue: "인증 방법 없음 (DEBUG)")
            #endif
            }
        }
        
        var description: String {
            switch self {
            case .pam:
                return String(localized: "settings.security.auth_method.template.pam.description", defaultValue: "사용자명-비밀번호 인증을 허용합니다.")
            case .simplePassword:
                return String(localized: "settings.security.auth_method.template.simple_password.description", defaultValue: "비밀번호만을 사용한 인증을 허용합니다. (보안 문제가 발생할 수 있으므로 권장하지 않습니다.)")
            case .sshKey:
                return String(localized: "settings.security.auth_method.template.ssh_key.description", defaultValue: "SSH 키 인증을 허용합니다.")
            #if DEBUG
            case .null:
                return String(localized: "settings.security.auth_method.template.null.description", defaultValue: "아무런 인증도 요구하지 않습니다. (보안 문제가 발생할 수 있으므로 권장하지 않습니다.)")
            #endif
            }
        }
    }
    
    enum PAMAllowMode: String, Identifiable {
        case user
        case group
        
        var id: String { rawValue }
    }
}

#if DEBUG
#Preview {
    AuthMethodContainer(authMethods: .constant([
    ]))
    .padding()
}
#endif
