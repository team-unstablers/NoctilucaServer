//
//  AuthChallengeSheetView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/10/25.
//

import SwiftUI
import SiriusKitClient

enum AuthChallengeSheetAction {
    case confirm(entry: ClientAuthEntry)
    case cancel
}

typealias AuthChallengeSheetActionHandler = (AuthChallengeSheetAction) -> Void

struct AuthChallengeSheetView: View {
    let authChallenge: AuthChallenge
    let handler: AuthChallengeSheetActionHandler

    @StateObject private var viewModel: AuthChallengeSheetViewModel

    init(authChallenge: AuthChallenge, availableMethods: [ClientAuthMethod], handler: @escaping AuthChallengeSheetActionHandler) {
        self.authChallenge = authChallenge
        self.handler = handler
        _viewModel = StateObject(wrappedValue: AuthChallengeSheetViewModel(authChallenge: authChallenge, availableMethods: availableMethods))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(markdown: String(localized: "auth.challenge.title", defaultValue: "인증 챌린지를 받았습니다"))
                .font(.headline)
                .padding(.bottom, 4)
                .foregroundStyle(.primary)
            Text(String(format: String(localized: "auth.challenge.server_message_format", defaultValue: "서버의 메시지: %@"), authChallenge.message ?? String(localized: "auth.challenge.no_message", defaultValue: "(없음)")))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.bottom, 12)

            authFormBody

            HStack {
                Spacer()
                Button(String(localized: "common.cancel", defaultValue: "취소"), role: .cancel) {
                    handler(.cancel)
                }
                .keyboardShortcut(.escape)
                Button(String(localized: "common.confirm", defaultValue: "확인"), role: .compatibleConfirm) {
                    submit()
                }
                .disabled(!viewModel.canSubmit)
            }
        }
        .padding(24)
    }

    @ViewBuilder
    private var authFormBody: some View {
        if viewModel.availableMethods.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(markdown: String(localized: "auth.challenge.no_methods_available", defaultValue: "지원 가능한 인증 방법이 없습니다."))
                    .foregroundStyle(.secondary)
                Text(markdown: String(localized: "auth.challenge.no_methods_detail", defaultValue: "서버가 요구하는 인증 방법을 클라이언트가 지원하지 않습니다."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 12)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.availableMethods.count > 1 {
                    Picker(String(localized: "auth.challenge.method_picker", defaultValue: "인증 방법"), selection: $viewModel.selectedMethod) {
                        ForEach(viewModel.availableMethods, id: \.rawValue) { method in
                            Text(method.displayName)
                                .tag(method)
                        }
                    }
                    .pickerStyle(.segmented)
                } else if let method = viewModel.availableMethods.first {
                    Text(method.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                authFormInputs
            }
            .padding(12)
            .background(Color.gray.mix(with: .white, by: 0.9))
            .clipShape(.rect(cornerRadius: 8))
            .padding(.bottom, 12)
        }
    }

    @ViewBuilder
    private var authFormInputs: some View {
        switch viewModel.selectedMethod {
        case .password:
            VStack(alignment: .leading, spacing: 8) {
                Text(markdown: String(localized: "auth.challenge.username_label", defaultValue: "사용자명"))
                TextField(String(localized: "auth.challenge.username_placeholder", defaultValue: "사용자명 입력"), text: $viewModel.username)
#if os(iOS)
                    .textInputAutocapitalization(.never)
#endif
                    .textFieldStyle(.roundedBorder)
                Text(markdown: String(localized: "auth.challenge.password_label", defaultValue: "비밀번호"))
                SecureField(String(localized: "auth.challenge.password_placeholder", defaultValue: "비밀번호 입력"), text: $viewModel.password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submit() }
            }
        case .simplePassword:
            VStack(alignment: .leading, spacing: 8) {
                Text(markdown: String(localized: "auth.challenge.password_label", defaultValue: "비밀번호"))
                SecureField(String(localized: "auth.challenge.password_placeholder", defaultValue: "비밀번호 입력"), text: $viewModel.simplePassword)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submit() }
            }
        case .sshKey:
            Text(markdown: String(localized: "auth.challenge.ssh_key_not_supported", defaultValue: "SSH 키 인증은 아직 지원되지 않습니다."))
                .foregroundStyle(.secondary)
        default:
            Text(markdown: String(localized: "auth.challenge.unsupported_method", defaultValue: "지원되지 않는 인증 방법입니다."))
                .foregroundStyle(.secondary)
        }
    }

    private func submit() {
        guard let entry = viewModel.makeEntry() else { return }
        handler(.confirm(entry: entry))
    }
}

#Preview {
    let authChallenge = AuthChallenge(
        acceptedMethods: ["password", "app.noctiluca.server.auth.simple-password"],
        nonce: Data(),
        message: "제한 구역입니다"
    )

    AuthChallengeSheetView(
        authChallenge: authChallenge,
        availableMethods: [.password, .simplePassword]
    ) { action in
        print(action)
    }
}
