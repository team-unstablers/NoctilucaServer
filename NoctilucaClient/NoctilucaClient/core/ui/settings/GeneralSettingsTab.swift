import SwiftUI

struct GeneralSettingsTab: View {
    @EnvironmentObject
    private var settingsStore: SettingsStore

    @State
    var shouldPresentDefaultConnectionSettingsSheet: Bool = false
    
    var body: some View {
        Form {
            Section(String(localized: "settings.general.title", defaultValue: "일반")) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text(String(localized: "settings.general.default_connection.title", defaultValue: "기본 연결 설정"))
                        Text(String(localized: "settings.general.default_connection.description", defaultValue: "빠른 연결 시 사용할 기본 설정을 변경합니다."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Button(String(localized: "common.settings", defaultValue: "설정…")) {
                            shouldPresentDefaultConnectionSettingsSheet = true
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                .sheet(isPresented: $shouldPresentDefaultConnectionSettingsSheet) {
                    SessionSettingsSheet(
                        scope: .global,
                        sessionSettings: $settingsStore.settings.sessionDefaults,
                    ) { action in
                        switch action {
                        case .cancel:
                            shouldPresentDefaultConnectionSettingsSheet = false
                        case .save:
                            settingsStore.save()
                            shouldPresentDefaultConnectionSettingsSheet = false
                        default:
                            shouldPresentDefaultConnectionSettingsSheet = false
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}
