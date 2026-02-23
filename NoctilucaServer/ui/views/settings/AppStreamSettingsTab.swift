import SwiftUI

struct AppStreamSettingsTab: View {
    
    @Binding
    var settings: AppSettings
    
    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "settings.app_stream.enable", defaultValue: "AppStream 활성화"), isOn: $settings.appStream.enabled)
                
                if settings.appStream.enabled {
                    AppStreamAllowedAppListContainer(allowedApps: $settings.appStream.allowedApps)
                }
                
            } header: {
                Text(markdown: String(localized: "settings.app_stream.title", defaultValue: "AppStream (실험 단계)"))
                Text(markdown: String(localized: "settings.app_stream.description", defaultValue: "AppStream은 Sirius 프로토콜의 프로젝션 채널을 활용하여, 앱 단위 프로젝션을 지원하는 실험적 기능입니다. 이 기능을 활성화하면, 클라이언트는 전체 디스플레이 대신 특정 앱의 창만 선택하여 프로젝션할 수 있습니다."))
            } footer: {
                Text(markdown: String(localized: "settings.app_stream.disclaimer", defaultValue: "현재 AppStream은 동시에 최대 1개의 앱만 프로젝션할 수 있으며, 일부 앱에서는 호환성 문제가 발생할 수 있습니다. 또한, 이 기능은 실험 단계에 있으므로 예기치 않은 동작이 발생할 수 있습니다."))
            }
            
            if settings.appStream.enabled {
                Section {
                    Toggle(isOn: .constant(true)) {
                        Text(markdown: String(localized: "settings.app_stream.disable_common_shortcuts.title", defaultValue: "앱 포커스를 뺏어갈 수 있는 시스템 단축키 무시하기"))
                        Text(markdown: String(localized: "settings.app_stream.disable_common_shortcuts.description", defaultValue: "AppStream이 활성화 된 동안, ⌘+Tab 같은 앱 포커스를 뺏어갈 가능성이 있는 시스템 단축키를 무시하여, 프로젝션된 앱이 더 원활하게 작동하도록 합니다."))
                    }
                    
                    Toggle(isOn: .constant(true)) {
                        Text(markdown: String(localized: "settings.app_stream.ignore_invisible_windows.title", defaultValue: "보이지 않는 윈도우 무시하기"))
                        Text(markdown: String(localized: "settings.app_stream.ignore_invisible_windows.description", defaultValue: "일부 앱에서는 기능 보조를 위해 보이지 않는 윈도우를 생성할 수 있습니다.\n이러한 윈도우까지 프로젝션을 수행하게 되면 예기치 않은 동작이 발생할 수 있습니다."))
                    }
                } header: {
                    Text(markdown: String(localized: "settings.app_stream.advanced.title", defaultValue: "고급 설정"))
                }
            }
        }
        .formStyle(.grouped)
    }
}
