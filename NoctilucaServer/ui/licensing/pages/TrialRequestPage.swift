//
//  TrialRequestPage.swift
//  NoctilucaServer
//

import SwiftUI

struct TrialRequestPage: View {
    var navigation: LicensingNavigationModel

    @State private var phase: Phase = .info
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var verificationCode: String = ""
    @State private var sessionId: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false

    private enum Phase {
        case info
        case verification
    }

    private let apiClient = LicenseAPIClient()

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                switch phase {
                case .info:
                    infoPhase
                case .verification:
                    verificationPhase
                }

                Divider()

                HStack {
                    Button(String(localized: "licensing.trial.back", defaultValue: "뒤로")) {
                        if phase == .verification {
                            phase = .info
                        } else {
                            navigation.goBack()
                        }
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    switch phase {
                    case .info:
                        Button(String(localized: "licensing.trial.request_code", defaultValue: "인증 코드 요청")) {
                            requestTrialCode()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canRequestCode)
                    case .verification:
                        Button(String(localized: "licensing.trial.confirm", defaultValue: "확인")) {
                            confirmVerificationCode()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(verificationCode.isEmpty)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .disabled(isLoading)

            if isLoading {
                ZStack {
                    Color.black.opacity(0.15)
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text(String(localized: "licensing.trial.loading", defaultValue: "서버와 통신 중입니다…"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .alert(
            String(localized: "licensing.trial.error_title", defaultValue: "체험판 요청 실패"),
            isPresented: $showError,
            presenting: errorMessage
        ) { _ in
            Button(String(localized: "licensing.trial.error_ok", defaultValue: "확인")) { }
        } message: { message in
            Text(message)
        }
    }

    private var infoPhase: some View {
        Form {
            Section {
                TextField(
                    String(localized: "licensing.trial.name", defaultValue: "이름"),
                    text: $name
                )

                TextField(
                    String(localized: "licensing.trial.email", defaultValue: "이메일 주소"),
                    text: $email
                )
            } header: {
                Text(String(localized: "licensing.trial.info_header", defaultValue: "체험판 시작"))
                Text("")
            } footer: {
                Text(String(localized: "licensing.trial.info_footer", defaultValue: "7일간 무료로 체험할 수 있습니다. 이메일 인증이 필요합니다."))
            }
        }
        .formStyle(.grouped)
    }

    private var verificationPhase: some View {
        Form {
            Section {
                TextField(
                    String(localized: "licensing.trial.verification_code", defaultValue: "인증 코드"),
                    text: $verificationCode
                )
                .font(.system(.body, design: .monospaced))
            } header: {
                Text(String(localized: "licensing.trial.verification_header", defaultValue: "인증 코드 입력"))
                Text("")
            } footer: {
                Text("\(email)(으)로 전송된 인증 코드를 입력해 주세요. 인증 코드는 10분 이내에 입력해야 합니다.")
            }
        }
        .formStyle(.grouped)
    }

    private var canRequestCode: Bool {
        !name.isEmpty && !email.isEmpty
    }

    private func requestTrialCode() {
        guard let hwid = SystemCapability.hardwareIdentifier() else {
            errorMessage = String(localized: "licensing.trial.error_hwid", defaultValue: "하드웨어 식별자를 가져올 수 없습니다.")
            showError = true
            return
        }

        isLoading = true

        Task {
            do {
                let response = try await apiClient.requestTrial(name: name, email: email, hwid: hwid)
                await MainActor.run {
                    sessionId = response.sessionId
                    isLoading = false
                    phase = .verification
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    handleError(error)
                }
            }
        }
    }

    private func confirmVerificationCode() {
        guard let hwid = SystemCapability.hardwareIdentifier() else {
            errorMessage = String(localized: "licensing.trial.error_hwid", defaultValue: "하드웨어 식별자를 가져올 수 없습니다.")
            showError = true
            return
        }

        isLoading = true

        Task {
            do {
                let response = try await apiClient.issueTrial(
                    sessionId: sessionId,
                    verificationCode: verificationCode,
                    hwid: hwid
                )
                try await LicenseManager.shared.installTrialLicense(
                    name: name,
                    email: email,
                    licenseKey: response.licenseKey,
                    seatProof: response.seatProof
                )
                await MainActor.run {
                    isLoading = false
                    navigation.onLicenseInstalled?()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    handleError(error)
                }
            }
        }
    }

    private func handleError(_ error: Error) {
        if let apiError = error as? LicenseAPIClientError {
            switch apiError {
            case .serverError(let statusCode, let detail):
                if statusCode == 409 {
                    errorMessage = String(localized: "licensing.trial.error_duplicate", defaultValue: "이 이메일 주소로는 이미 체험판이 발급되었습니다.")
                } else {
                    errorMessage = detail ?? String(localized: "licensing.trial.error_server", defaultValue: "서버 오류가 발생했습니다.")
                }
            case .networkError:
                errorMessage = String(localized: "licensing.trial.error_network", defaultValue: "네트워크에 연결할 수 없습니다.")
            }
        } else {
            errorMessage = error.localizedDescription
        }
        showError = true
    }
}
