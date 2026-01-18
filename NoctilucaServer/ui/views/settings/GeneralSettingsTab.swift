import SwiftUI

struct GeneralSettingsTab: View {
    @Binding
    var settings: AppSettings

    var body: some View {
        Form {
            Section(String(localized: "settings.general.title", defaultValue: "일반")) {
                Toggle(isOn: .constant(false)) {
                    Text(String(localized: "settings.general.autolaunch.title", defaultValue: "시스템 기동 시 자동으로 Noctiluca 시작하기"))
                }
                
                Toggle(isOn: $settings.general.autoStart) {
                    Text(String(localized: "settings.general.autostart.title", defaultValue: "앱 기동 시 자동으로 서버 시작하기"))
                    Text(String(localized: "settings.general.autostart.description", defaultValue: "Noctiluca Server 앱이 실행될 때 서버를 자동으로 시작합니다."))
                }

                IntegerField(value: $settings.general.maxConcurrentSessions) {
                    Text(String(localized: "settings.general.max_concurrent_sessions.title", defaultValue: "최대 동시 접속 수"))
                    Text(String(localized: "settings.general.max_concurrent_sessions.description", defaultValue: "Noctiluca가 허용할 최대 동시 접속 수를 설정합니다."))
                }
            }

            Section(String(localized: "settings.notification.title", defaultValue: "알림")) {
                Toggle(isOn: $settings.notifications.enabled) {
                    Text(String(localized: "settings.notification.enabled.title", defaultValue: "알림 표시하기"))
                    Text(String(localized: "settings.notification.enabled.description", defaultValue: "이벤트 발생 시 알림을 표시합니다."))
                }
                
                if settings.notifications.enabled {
                    Toggle(String(localized: "settings.notification.on_connect", defaultValue: "사용자가 접속했을 때"), isOn: .constant(true))
                    Toggle(String(localized: "settings.notification.on_disconnect", defaultValue: "사용자가 접속을 종료했을 때"), isOn: .constant(true))
                    Toggle(String(localized: "settings.notification.on_error", defaultValue: "오류가 발생했을 때"), isOn: .constant(true))
                }

            }
        }
        .formStyle(.grouped)
    }
}
