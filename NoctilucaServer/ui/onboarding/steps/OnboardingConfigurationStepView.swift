//
//  OnboardingConfigurationStepView.swift
//  NoctilucaServer
//

import SwiftUI

struct OnboardingConfigurationStepView: View {
    @State private var serverName: String = Host.current().localizedName ?? "Noctiluca Server"
    @State private var password: String = ""
    @State private var passwordConfirmation: String = ""

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Text(String(localized: "onboarding.configuration.title", defaultValue: "기본 설정"))
                .font(.largeTitle)
                .fontWeight(.bold)

            Text(String(localized: "onboarding.configuration.description", defaultValue: "서버의 기본 설정을 구성합니다."))
                .font(.title3)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "onboarding.configuration.server_name.title", defaultValue: "서버 이름"))
                        .font(.headline)
                    Text(String(localized: "onboarding.configuration.server_name.description", defaultValue: "클라이언트에서 이 서버를 식별하는 데 사용됩니다."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    TextField(
                        String(localized: "onboarding.configuration.server_name.placeholder", defaultValue: "서버 이름"),
                        text: $serverName
                    )
                    .textFieldStyle(.roundedBorder)
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "onboarding.configuration.password.title", defaultValue: "접속 비밀번호"))
                        .font(.headline)
                    Text(String(localized: "onboarding.configuration.password.description", defaultValue: "클라이언트가 이 서버에 접속할 때 사용할 비밀번호입니다."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    SecureField(
                        String(localized: "onboarding.configuration.password.placeholder", defaultValue: "비밀번호"),
                        text: $password
                    )
                    .textFieldStyle(.roundedBorder)
                    SecureField(
                        String(localized: "onboarding.configuration.password_confirm.placeholder", defaultValue: "비밀번호 확인"),
                        text: $passwordConfirmation
                    )
                    .textFieldStyle(.roundedBorder)
                }
            }
            .frame(maxWidth: 480)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    OnboardingConfigurationStepView()
        .frame(width: 780, height: 460)
}
