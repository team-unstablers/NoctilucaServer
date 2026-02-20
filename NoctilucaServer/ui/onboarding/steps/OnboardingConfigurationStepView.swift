//
//  OnboardingConfigurationStepView.swift
//  NoctilucaServer
//

import SwiftUI

struct OnboardingConfigurationStepView: View {
    @EnvironmentObject
    var settingsStore: SettingsStore
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Text(markdown: String(localized: "onboarding.configuration.title", defaultValue: "기본 설정"))
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text(markdown: String(localized: "onboarding.configuration.description", defaultValue: "서버의 기본 설정을 구성합니다."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(markdown: String(localized: "settings.security.auth_methods.title", defaultValue: "인증 수단"))
                        .font(.headline)
                        .padding(.bottom, 4)
                    Text(markdown: String(localized: "settings.security.auth_methods.description", defaultValue: "이 컴퓨터에 접속할 때 사용할 인증 수단을 설정합니다. 드래그-드롭으로 우선 순위를 변경할 수 있습니다. [더 알아보기…](http://google.com)"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                    
                    // AuthMethodContainer(authMethods: $settingsStore.settings.security.allowedEntries)
                }
                .padding()
                .background(.background.secondary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                

                /*
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text(markdown: String(localized: "onboarding.configuration.password.title", defaultValue: "접속 비밀번호"))
                        .font(.headline)
                    Text(markdown: String(localized: "onboarding.configuration.password.description", defaultValue: "클라이언트가 이 서버에 접속할 때 사용할 비밀번호입니다."))
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
                 */
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
