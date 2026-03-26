import ServiceManagement
import SwiftUI

import Sparkle

struct GeneralSettingsTab: View {
    @Binding
    var settings: AppSettings

    @State
    private var launchAtLogin: Bool = false

    @State
    private var launchAtLoginRequiresApproval: Bool = false
    
    @State
    private var automaticallyChecksForUpdates: Bool = AppUpdater.shared.updaterController.updater.automaticallyChecksForUpdates
    
    @State
    private var automaticallyDownloadsUpdates: Bool = AppUpdater.shared.updaterController.updater.automaticallyDownloadsUpdates
    
    

    var body: some View {
        Form {
            Section(String(localized: "settings.general.title", defaultValue: "일반")) {
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
                
                Toggle(isOn: $settings.general.autoStart) {
                    Text(markdown: String(localized: "settings.general.autostart.title", defaultValue: "앱 기동 시 자동으로 서버 시작하기"))
                    Text(markdown: String(localized: "settings.general.autostart.description", defaultValue: "Noctiluca Server 앱이 실행될 때 서버를 자동으로 시작합니다."))
                }

                IntegerField(value: $settings.general.maxConcurrentSessions) {
                    Text(markdown: String(localized: "settings.general.max_concurrent_sessions.title", defaultValue: "최대 동시 접속 수"))
                    Text(markdown: String(localized: "settings.general.max_concurrent_sessions.description", defaultValue: "Noctiluca가 허용할 최대 동시 접속 수를 설정합니다."))
                }
                
                Toggle(isOn: $automaticallyChecksForUpdates) {
                    Text(markdown: String(localized: "settings.general.autoupdate.check.title", defaultValue: "자동으로 업데이트 확인하기"))
                    Text(markdown: String(localized: "settings.general.autoupdate.check.description", defaultValue: "자동으로 Noctiluca Server의 업데이트를 확인합니다."))
                }
                .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                    AppUpdater.shared.updaterController.updater.automaticallyChecksForUpdates = newValue
                }
                
                Toggle(isOn: $automaticallyDownloadsUpdates) {
                    Text(markdown: String(localized: "settings.general.autoupdate.download.title", defaultValue: "자동으로 업데이트 다운로드하기"))
                    Text(markdown: String(localized: "settings.general.autoupdate.download.description", defaultValue: "자동으로 Noctiluca Server의 업데이트를 다운로드합니다."))
                }
                .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                    AppUpdater.shared.updaterController.updater.automaticallyDownloadsUpdates = newValue
                }
            }

            Section(String(localized: "settings.notification.title", defaultValue: "알림")) {
                Toggle(isOn: $settings.notifications.enabled) {
                    Text(markdown: String(localized: "settings.notification.enabled.title", defaultValue: "알림 표시하기"))
                    Text(markdown: String(localized: "settings.notification.enabled.description", defaultValue: "이벤트 발생 시 알림을 표시합니다."))
                }
            }
            
            Section {
                if settings.notifications.enabled {
                    Toggle(String(localized: "settings.notification.on_connect", defaultValue: "사용자가 접속했을 때"), isOn: .constant(true))
                    Toggle(String(localized: "settings.notification.on_disconnect", defaultValue: "사용자가 접속을 종료했을 때"), isOn: .constant(true))
                    Toggle(String(localized: "settings.notification.on_error", defaultValue: "오류가 발생했을 때"), isOn: .constant(true))
                }
            }
            
            Section {
                Toggle(String(localized: "settings.notification.on_clipboard_access", defaultValue: "클립보드 내용에 접근했을 때"), isOn: .constant(false))
                
                Toggle(String(localized: "settings.notification.on_file_transfer", defaultValue: "파일 전송이 시작되었을 때"), isOn: .constant(true))
            }
        }
        .formStyle(.grouped)
        .onAppear {
            syncLaunchAtLoginStatus()
        }
    }

    private func syncLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        launchAtLogin = (status == .enabled)
        launchAtLoginRequiresApproval = (status == .requiresApproval)
    }
}
