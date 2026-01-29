import SwiftUI

struct MiscSettingsTab: View {
    @Binding
    var settings: AppSettings

    var body: some View {
        Form {
            Section(String(localized: "settings.misc.telemetry.title", defaultValue: "텔레메트리 및 진단 정보")) {
                Toggle(isOn: $settings.telemetry.enableTelemetry) {
                    Text(markdown: String(localized: "settings.misc.telemetry.enable.title", defaultValue: "Noctiluca의 개발을 익명으로 돕기"))
                    Text(markdown: String(localized: "settings.misc.telemetry.enable.description", defaultValue: "사용자 환경 및 사용 통계를 익명으로 수집하는 것을 허용합니다.\n프라이버시 보호를 우선하기 위해, 이 옵션은 기본적으로 꺼져 있습니다. [더 알아보기…](http://google.com)"))
                }
                SettingsEntry(title: String(localized: "settings.misc.telemetry.identifier.title", defaultValue: "텔레메트리 식별자")) {
                    Button(String(localized: "settings.misc.telemetry.identifier.reset", defaultValue: "식별자 재설정")) {

                    }
                }

                SettingsEntry(title: String(localized: "settings.misc.diagnostics.export.title", defaultValue: "진단 정보 내보내기")) {
                    Button(String(localized: "settings.misc.diagnostics.export.save_to_file", defaultValue: "파일로 저장…")) {

                    }
                }
                SettingsEntry(title: String(localized: "settings.misc.connectivity_test.title", defaultValue: "외부 접속 테스트"), subtitle: String(localized: "settings.misc.connectivity_test.description", defaultValue: "주식회사 팀언스테이블러즈에서 제공하는 테스트 노드를 통해 외부로부터 접속이 가능한지 테스트합니다.")) {
                    Button(String(localized: "settings.misc.connectivity_test.request", defaultValue: "접속 테스트 요청하기")) {}
                }
            }
        }
        .formStyle(.grouped)
    }
}
