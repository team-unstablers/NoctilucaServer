//
//  OnboardingPreferencesStepView.swift
//  NoctilucaServer
//

import ServiceManagement
import SwiftUI

import Sparkle

struct OnboardingPreferencesStepView: View {
    @State
    private var launchAtLogin: Bool = false

    @State
    private var launchAtLoginRequiresApproval: Bool = false

    @State
    private var automaticallyChecksForUpdates: Bool = AppUpdater.shared.updaterController.updater.automaticallyChecksForUpdates

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 16) {
                Text(markdown: String(localized: "onboarding.preferences.title", defaultValue: "환경 설정"))
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(markdown: String(localized: "onboarding.preferences.description", defaultValue: "사용 환경에 맞게 추가 설정을 구성합니다."))
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                Toggle(isOn: $launchAtLogin) {
                    Text(markdown: String(localized: "settings.general.autolaunch.scoped.title", defaultValue: "사용자 로그온 시 자동으로 Noctiluca Server 시작하기"))
                    Text(markdown: String(localized: "settings.general.autolaunch.scoped.description", defaultValue: "현재 사용자가 시스템에 로그온 시 자동으로 Noctiluca Server를 시작합니다."))
                }
                .onChange(of: launchAtLogin) { _, newValue in
                    let currentlyEnabled = SMAppService.mainApp.status == .enabled
                    guard newValue != currentlyEnabled else { return }
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {}
                    syncLaunchAtLoginStatus()
                }

                if launchAtLoginRequiresApproval {
                    HStack(spacing: 4) {
                        Text(String(localized: "settings.general.autolaunch.scoped.requires_approval", defaultValue: "시스템 설정에서 승인이 필요합니다."))
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                        Button(String(localized: "settings.general.autolaunch.scoped.open_settings", defaultValue: "로그인 항목 설정 열기…")) {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                        .font(.subheadline)
                    }
                }

                Divider()

                Toggle(isOn: $automaticallyChecksForUpdates) {
                    Text(markdown: String(localized: "settings.general.autoupdate.check.title", defaultValue: "자동으로 업데이트 확인하기"))
                    Text(markdown: String(localized: "settings.general.autoupdate.check.description", defaultValue: "자동으로 Noctiluca Server의 업데이트를 확인합니다."))
                }
                .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                    AppUpdater.shared.updaterController.updater.automaticallyChecksForUpdates = newValue
                }
            }
            .padding()
            .background(.background.secondary)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 480)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            applyDefaults()
            syncLaunchAtLoginStatus()
        }
    }

    private func applyDefaults() {
        let status = SMAppService.mainApp.status
        if status != .enabled {
            do {
                try SMAppService.mainApp.register()
            } catch {}
        }

        AppUpdater.shared.updaterController.updater.automaticallyChecksForUpdates = true
        automaticallyChecksForUpdates = true
    }

    private func syncLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = (status == .enabled)
        launchAtLoginRequiresApproval = (status == .requiresApproval)
    }
}

#Preview {
    OnboardingPreferencesStepView()
        .frame(width: 780, height: 460)
}
