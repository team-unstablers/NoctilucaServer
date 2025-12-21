import SwiftUI

struct GeneralSettingsTab: View {
    @State
    var shouldPresentDefaultConnectionSettingsSheet: Bool = false
    
    var body: some View {
        Form {
            Section("일반") {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text("기본 연결 설정")
                        Text("빠른 연결 시 사용할 기본 설정을 변경합니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Button("설정…") {
                            shouldPresentDefaultConnectionSettingsSheet = true
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .sheet(isPresented: $shouldPresentDefaultConnectionSettingsSheet) {
                    SessionSettingsSheet()
                }
            }
        }
        .formStyle(.grouped)
    }
}
