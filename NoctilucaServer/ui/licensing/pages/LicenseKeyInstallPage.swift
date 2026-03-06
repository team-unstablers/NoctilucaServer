//
//  LicenseKeyInstallPage.swift
//  NoctilucaServer
//

import SwiftUI

struct LicenseKeyInstallPage: View {
    var navigation: LicensingNavigationModel

    @State private var computerName: String = Host.current().localizedName ?? "Mac"
    @State private var ownerName: String = ""
    @State private var email: String = ""
    @State private var licenseKey: String = ""
    @State private var isInstalling: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Form {
                    Section {
                        TextField(
                            String(localized: "licensing.install.computer_name", defaultValue: "컴퓨터 이름"),
                            text: $computerName
                        )

                        TextField(
                            String(localized: "licensing.install.owner_name", defaultValue: "라이선스 소유자"),
                            text: $ownerName
                        )

                        TextField(
                            String(localized: "licensing.install.email", defaultValue: "이메일 주소"),
                            text: $email
                        )

                        LabeledContent(String(localized: "licensing.install.license_key", defaultValue: "라이선스 키")) {
                            TextEditor(text: $licenseKey)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 80)
                                .scrollContentBackground(.hidden)
                                .padding(4)
                                .background(.background)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.secondary.opacity(0.2))
                                )
                        }
                    } header: {
                        Text(String(localized: "licensing.install.header", defaultValue: "라이선스 등록"))
                        Text("")
                    }
                }
                .formStyle(.grouped)

                Divider()

                HStack {
                    Button(String(localized: "licensing.install.back", defaultValue: "뒤로")) {
                        navigation.goBack()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button(String(localized: "licensing.install.install", defaultValue: "설치")) {
                        install()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canInstall)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .disabled(isInstalling)

            if isInstalling {
                ZStack {
                    Color.black.opacity(0.15)
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text(String(localized: "licensing.install.installing", defaultValue: "라이선스 서버와 통신 중입니다…"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .alert(
            String(localized: "licensing.install.error_title", defaultValue: "라이선스 설치 실패"),
            isPresented: $showError,
            presenting: errorMessage
        ) { _ in
            Button(String(localized: "licensing.install.error_ok", defaultValue: "확인")) { }
        } message: { message in
            Text(message)
        }
        .onAppear {
            if let retryInfo = navigation.licenseInfoForRetry {
                ownerName = retryInfo.name
                email = retryInfo.email
                licenseKey = retryInfo.licenseKey
                navigation.licenseInfoForRetry = nil
            }
        }
    }

    private var canInstall: Bool {
        !computerName.isEmpty && !ownerName.isEmpty && !email.isEmpty && !licenseKey.isEmpty
    }

    private func install() {
        let trimmedKey = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let info = LicenseInfo(name: ownerName, email: email, licenseKey: trimmedKey)

        isInstalling = true

        Task {
            do {
                try await LicenseManager.shared.installLicense(info)
                await MainActor.run {
                    isInstalling = false
                    navigation.onLicenseInstalled?()
                }
            } catch let error as LicenseManagerError {
                await MainActor.run {
                    isInstalling = false
                    handleInstallError(error, licenseInfo: info)
                }
            } catch {
                await MainActor.run {
                    isInstalling = false
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
        }
    }

    private func handleInstallError(_ error: LicenseManagerError, licenseInfo: LicenseInfo) {
        switch error {
        case .installationFailed(let underlyingError):
            if let apiError = underlyingError as? LicenseAPIClientError {
                switch apiError {
                case .serverError(let statusCode, let detail) where statusCode == 409:
                    // 시트 가득 참 → 시트 관리 페이지로 이동
                    navigation.licenseInfoForRetry = licenseInfo
                    navigation.navigateTo(.seatManagement)
                    return
                case .serverError(_, let detail):
                    errorMessage = detail ?? String(localized: "licensing.install.error_server", defaultValue: "서버 오류가 발생했습니다.")
                case .networkError:
                    errorMessage = String(localized: "licensing.install.error_network", defaultValue: "네트워크에 연결할 수 없습니다.")
                }
            } else {
                errorMessage = underlyingError?.localizedDescription ?? String(localized: "licensing.install.error_unknown", defaultValue: "알 수 없는 오류가 발생했습니다.")
            }
        case .noHardwareIdentifier:
            errorMessage = String(localized: "licensing.install.error_hwid", defaultValue: "하드웨어 식별자를 가져올 수 없습니다.")
        case .invalidState:
            errorMessage = String(localized: "licensing.install.error_state", defaultValue: "현재 상태에서 라이선스를 설치할 수 없습니다.")
        }
        showError = true
    }
}
