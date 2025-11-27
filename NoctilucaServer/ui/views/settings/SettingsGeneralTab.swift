import SwiftUI

struct SettingsGeneralTab: View {
    var body: some View {
        Form {
            Section("일반") {
                Toggle(isOn: .constant(true)) {
                    Text("시스템 기동 시 자동으로 Noctiluca 시작하기")
                }

                TextField(text: .constant("2")) {
                    Text("최대 동시 접속 수")
                    Text("Noctiluca가 허용할 최대 동시 접속 수를 설정합니다.")
                }
            }

            Section("알림") {
                Toggle(isOn: .constant(true)) {
                    Text("사용자에게 알림 표시하기")
                    Text("...")
                }

                Toggle("사용자가 접속했을 때", isOn: .constant(true))
                Toggle("사용자가 접속을 종료했을 때", isOn: .constant(true))
                Toggle("오류가 발생했을 때", isOn: .constant(true))

            }
        }
        .formStyle(.grouped)
    }
}
