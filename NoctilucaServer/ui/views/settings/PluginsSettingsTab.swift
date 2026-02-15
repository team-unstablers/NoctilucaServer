import SwiftUI

enum PluginSecurityPolicy: Hashable {
    case disallowAll
    case allowTeamUnstablers
    case allowSignedOnly
    case allowAny
}

struct PluginsSettingsTab: View {

    @Binding
    var settings: AppSettings
    
    @State
    var securityPolicy: PluginSecurityPolicy = .disallowAll

    var body: some View {
        Form {
            Section(String(localized: "settings.plugins.title", defaultValue: "플러그인 설정")) {
                Picker(selection: $securityPolicy) {
                    VStack(alignment: .leading) {
                        Text(markdown: String(localized: "settings.plugins.security_policy.disallow_all.title", defaultValue: "모든 플러그인 차단"))
                        Text(markdown: String(localized: "settings.plugins.security_policy.disallow_all.description", defaultValue: "Noctiluca Server에 내장되거나 번들된 플러그인 외에는 모두 차단합니다."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                        .tag(PluginSecurityPolicy.disallowAll)

                    VStack(alignment: .leading) {
                        Text(markdown: String(localized: "settings.plugins.security_policy.allow_team_unstablers.title", defaultValue: "공식 플러그인만 허용"))
                        Text(markdown: String(localized: "settings.plugins.security_policy.allow_team_unstablers.description", defaultValue: "Noctiluca의 개발사인 team unstablers Inc.에서 제공하는 공식 플러그인만 허용합니다."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                        .tag(PluginSecurityPolicy.allowTeamUnstablers)

                    VStack(alignment: .leading) {
                        Text(markdown: String(localized: "settings.plugins.security_policy.allow_signed.title", defaultValue: "서명된 플러그인만 허용 **(위험!)**"))
                        Text(markdown: String(localized: "settings.plugins.security_policy.allow_signed.description", defaultValue: "Apple로부터 신뢰받은 개발자들이 서명한 모든 플러그인을 허용합니다.\n**Apple로부터 신뢰를 받았더라도 안전하지 않은 플러그인이 있을 수 있습니다**"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                        .tag(PluginSecurityPolicy.allowSignedOnly)

                    VStack(alignment: .leading) {
                        Text(markdown: String(localized: "settings.plugins.security_policy.allow_any.title", defaultValue: "모든 플러그인 허용 **(위험!)**"))
                        Text(markdown: String(localized: "settings.plugins.security_policy.allow_any.description", defaultValue: "Ad-hoc 서명된 플러그인을 포함하여 모든 플러그인을 허용합니다.\n**악성 플러그인에 의해 시스템이 손상될 수 있습니다.**"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                        .tag(PluginSecurityPolicy.allowAny)

                } label: {
                    Text(markdown: String(localized: "settings.plugins.security_policy.label", defaultValue: "보안 정책"))
                    Text(markdown: String(localized: "settings.plugins.security_policy.description", defaultValue: "외부 플러그인에 대한 보안 정책을 설정합니다. 이 설정을 적용하려면 Noctiluca Server를 다시 기동해야 합니다."))
                }
                .pickerStyle(.inline)


                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text(markdown: String(localized: "settings.plugins.external_location.title", defaultValue: "외부 플러그인 위치"))
                        Text("")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Button(String(localized: "settings.plugins.external_location.open_in_finder", defaultValue: "Finder로 열기")) {}
                    }
                    .foregroundStyle(.secondary)
                }
            }
            
            Section {
                PluginBundleListContainer()
            } header: {
                Text(markdown: String(localized: "settings.plugins.loaded_bundles.title", defaultValue: "로드된 플러그인 번들 목록"))
            }
        }
        .formStyle(.grouped)
    }
}
