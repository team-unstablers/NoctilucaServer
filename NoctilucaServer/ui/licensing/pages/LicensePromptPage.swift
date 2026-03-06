//
//  LicensePromptPage.swift
//  NoctilucaServer
//

import SwiftUI

import Inject

struct LicensePromptPage: View {
    @ObserveInjection
    var inject

    @Environment(\.openURL)
    private var openURL

    var navigation: LicensingNavigationModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text(String(localized: "licensing.prompt.title", defaultValue: "라이선스가 필요합니다"))
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(String(localized: "licensing.prompt.subtitle", defaultValue: "Noctiluca Server를 사용하려면 라이선스를 등록하거나 체험판을 시작하세요."))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }

            VStack(spacing: 12) {
                Button {
                    navigation.navigateTo(.trialRequest)
                } label: {
                    Text(String(localized: "licensing.prompt.start_trial", defaultValue: "체험판 시작 (7일)"))
                        .frame(maxWidth: 240)
                }
                .controlSize(.large)

                Button {
                    navigation.navigateTo(.licenseKeyInstall)
                } label: {
                    Text(String(localized: "licensing.prompt.register_license", defaultValue: "라이선스 키 등록"))
                        .frame(maxWidth: 240)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)

                Button {
                    openURL(URL(string: "https://noctiluca.app/pricing")!)
                } label: {
                    Text(String(localized: "licensing.prompt.purchase", defaultValue: "구매하기…"))
                }
                .buttonStyle(.link)
            }

            Spacer()
        }
        .padding(32)
        .enableInjection()
    }
}
