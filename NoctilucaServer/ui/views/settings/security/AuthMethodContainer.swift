//
//  AuthMethodContainer.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation
import Collaboration

import SwiftUI

struct AuthMethodContainer: View {
    @Binding
    var authMethods: [AuthMethod]
    @State private var selection = Set<AuthMethod>()
    @State private var isAddSheetPresented = false
    
    init(authMethods: Binding<[AuthMethod]>) {
        self._authMethods = authMethods
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            List(selection: $selection) {
                ForEach(authMethods, id: \.self) { method in
                    AuthMethodEntry(method: method)
                        .tag(method)
                        .focusable(true)
                }
                .onMove(perform: moveAuthMethods)
            }
            .listStyle(.inset)
            .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            
            HStack {
                Spacer()
                Button("삭제", role: .destructive) {
                    removeSelected()
                }
                .disabled(selection.isEmpty)
                
                Button("추가") {
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
    var onSelect: (AuthMethod) -> Void
    
    @State private var selectedTemplate: TemplateKind = TemplateKind.available.first ?? .pam
    @State private var pamAllowMode: PAMAllowMode = .user
    @State private var pamPrincipal: String = NSUserName()
    @State private var simplePasswordHash: String = ""
    @State private var sshPublicKey: String = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINGHpezMcBEmby7zNaxPmj4cFPZ/P6zi3wcO5xC1LPZz cheesekun@cheese-mbpr14.local"
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("인증 방법 선택")
                .font(.title2.bold())
            Text("추가할 인증 방법을 선택하세요.")
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
                Button("취소") {
                    isPresented = false
                }
                Button("추가") {
                    // @codex, pam 인증 사용 시 CBIdentityPicker()를 사용하도록 해주세요
                    testCBIdentityPicker()
                }
                .disabled(!canCommitSelection)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 420, alignment: .topLeading)
    }
    
    private var canCommitSelection: Bool {
        switch selectedTemplate {
        case .pam:
            return !pamPrincipal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .simplePassword:
            return !simplePasswordHash.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .sshKey:
            return !sshPublicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        #if DEBUG
        case .none:
            return true
        #endif
        }
    }
    
    @ViewBuilder
    private var templateDetailInputs: some View {
        switch selectedTemplate {
        case .pam:
            VStack(alignment: .leading, spacing: 8) {
                Text("PAM 인증 세부 설정")
                    .font(.headline)
                Picker("허용 범위", selection: $pamAllowMode) {
                    Text("사용자").tag(PAMAllowMode.user)
                    Text("그룹").tag(PAMAllowMode.group)
                }
                .pickerStyle(.segmented)
                TextField(pamAllowMode == .user ? "허용 사용자 이름" : "허용 그룹 이름", text: $pamPrincipal)
                    .textFieldStyle(.roundedBorder)
            }
        case .simplePassword:
            VStack(alignment: .leading, spacing: 8) {
                Text("간단 비밀번호 인증")
                    .font(.headline)
                Text("비밀번호의 bcrypt 해시를 입력하세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("bcrypt 해시", text: $simplePasswordHash, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...3)
            }
        case .sshKey:
            VStack(alignment: .leading, spacing: 8) {
                Text("SSH 키 인증")
                    .font(.headline)
                Text("허용할 공개 키를 입력하세요.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("ssh-ed25519 AAAA...", text: $sshPublicKey, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2...4)
            }
        #if DEBUG
        case .none:
            EmptyView()
        #endif
        }
    }
    
    private func handleSubmit() {
        guard canCommitSelection else { return }
        let method = selectedAuthMethod()
        onSelect(method)
        isPresented = false
    }
    
    private func testCBIdentityPicker() {
        let picker = CBIdentityPicker()
        
        // 제목 설정
        picker.title = "원격 접속을 허용할 사용자를 선택하세요"
        
        // 여러 명 선택 가능 여부
        picker.allowsMultipleSelection = true
        
        // 윈도우 모달로 띄우기 (completionHandler로 결과 받음)
        picker.runModal()
        /*
        picker.runModal { (response) in
            if response == .OK {
                // 사용자가 선택한 목록 (CBIdentity 배열)
                let identities = picker.identities
                
                for identity in identities {
                    print("선택된 이름: \(identity.fullName ?? "이름 없음")")
                    print("계정명(ShortName): \(identity.posixName ?? "N/A")")
                    print("고유 ID(UUID): \(identity.uuidString)") // ★ 저장할 땐 이걸로!
                    
                    // 그룹인지 사용자인지 구분
                    if identity.type == .groupIdentity {
                        print("-> 이건 그룹입니다.")
                    }
                }
            }
        }
         */
    }
    
    private func selectedAuthMethod() -> AuthMethod {
        switch selectedTemplate {
        case .pam:
            let principal = pamPrincipal.trimmingCharacters(in: .whitespacesAndNewlines)
            let allowItem: PAMAuthAllowlistItem = pamAllowMode == .group ? .group(name: principal) : .user(name: principal)
            return .password(allows: allowItem)
        case .simplePassword:
            return .simplePassword(bcryptHash: simplePasswordHash.trimmingCharacters(in: .whitespacesAndNewlines))
        case .sshKey:
            return .sshKey(publicKey: sshPublicKey.trimmingCharacters(in: .whitespacesAndNewlines))
        #if DEBUG
        case .none:
            return .none
        #endif
        }
    }
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
        case none
        #endif
        
        var id: String { rawValue }
        
        static var available: [TemplateKind] {
            var values: [TemplateKind] = [.pam, .simplePassword, .sshKey]
            #if DEBUG
            values.append(.none)
            #endif
            return values
        }
        
        var title: String {
            switch self {
            case .pam:
                return "UNIX PAM 인증 (사용자명-비밀번호)"
            case .simplePassword:
                return "간단 비밀번호 인증 (권장하지 않음)"
            case .sshKey:
                return "SSH 키 인증"
            #if DEBUG
            case .none:
                return "인증 방법 없음 (DEBUG)"
            #endif
            }
        }
        
        var description: String {
            switch self {
            case .pam:
                return "사용자명-비밀번호 인증을 허용합니다."
            case .simplePassword:
                return "비밀번호만을 사용한 인증을 허용합니다. (보안 문제가 발생할 수 있으므로 권장하지 않습니다.)"
            case .sshKey:
                return "SSH 키 인증을 허용합니다."
            #if DEBUG
            case .none:
                return "아무런 인증도 요구하지 않습니다. (보안 문제가 발생할 수 있으므로 권장하지 않습니다.)"
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
        .password(allows: .user(name: "cheesekun")),
        .sshKey(publicKey: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINGHpezMcBEmby7zNaxPmj4cFPZ/P6zi3wcO5xC1LPZz cheesekun@cheese-mbpr14.local")
    ]))
    .padding()
}
#endif
