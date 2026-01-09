import SwiftUI

struct MiscSettingsTab: View {
    @Binding
    var settings: AppSettings

    var body: some View {
        Form {
            Section("텔레메트리 및 진단 정보") {
                Toggle(isOn: $settings.telemetry.enableTelemetry) {
                    Text("Noctiluca의 개발을 익명으로 돕기")
                    Text("사용자 환경 및 사용 통계를 익명으로 수집하는 것을 허용합니다.\n프라이버시 보호를 우선하기 위해, 이 옵션은 기본적으로 꺼져 있습니다. [더 알아보기…](http://google.com)")
                }
                SettingsEntry(title: "텔레메트리 식별자") {
                    Button("식별자 재설정") {

                    }
                }

                SettingsEntry(title: "진단 정보 내보내기") {
                    Button("파일로 저장…") {

                    }
                }
                SettingsEntry(title: "외부 접속 테스트", subtitle: "주식회사 팀언스테이블러즈에서 제공하는 테스트 노드를 통해 외부로부터 접속이 가능한지 테스트합니다.") {
                    Button("접속 테스트 요청하기") {}
                }
            }
        }
        .formStyle(.grouped)
    }
}
