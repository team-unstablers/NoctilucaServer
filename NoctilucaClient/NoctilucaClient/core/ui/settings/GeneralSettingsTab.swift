import SwiftUI

#if UNLEASHED_EDITION
import Sparkle
#endif

struct GeneralSettingsTab: View {
    @EnvironmentObject
    private var settingsStore: SettingsStore

    @State
    var shouldPresentDefaultConnectionSettingsSheet: Bool = false
    
#if UNLEASHED_EDITION
    @State
    private var automaticallyChecksForUpdates: Bool = AppUpdater.shared.updaterController.updater.automaticallyChecksForUpdates
    
    @State
    private var automaticallyDownloadsUpdates: Bool = AppUpdater.shared.updaterController.updater.automaticallyDownloadsUpdates
#endif
    
    
    var body: some View {
        Form {
            Section(String(localized: "settings.general.title", defaultValue: "일반")) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text(markdown: String(localized: "settings.general.default_connection.title", defaultValue: "기본 연결 설정"))
                        Text(markdown: String(localized: "settings.general.default_connection.description", defaultValue: "빠른 연결 시 사용할 기본 설정을 변경합니다."))
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
                
#if UNLEASHED_EDITION
                Toggle(isOn: $automaticallyChecksForUpdates) {
                    Text(markdown: String(localized: "settings.general.autoupdate.check.title", defaultValue: "자동으로 업데이트 확인하기"))
                    Text(markdown: String(localized: "settings.general.autoupdate.check.description", defaultValue: "자동으로 Noctiluca Navigator의 업데이트를 확인합니다."))
                }
                .onChange(of: automaticallyChecksForUpdates) { _, newValue in
                    AppUpdater.shared.updaterController.updater.automaticallyChecksForUpdates = newValue
                }
                
                Toggle(isOn: $automaticallyDownloadsUpdates) {
                    Text(markdown: String(localized: "settings.general.autoupdate.download.title", defaultValue: "자동으로 업데이트 다운로드하기"))
                    Text(markdown: String(localized: "settings.general.autoupdate.download.description", defaultValue: "자동으로 Noctiluca Navigator의 업데이트를 다운로드합니다."))
                }
                .onChange(of: automaticallyDownloadsUpdates) { _, newValue in
                    AppUpdater.shared.updaterController.updater.automaticallyDownloadsUpdates = newValue
                }
#endif
            }
        }
        .formStyle(.grouped)
    }
}
