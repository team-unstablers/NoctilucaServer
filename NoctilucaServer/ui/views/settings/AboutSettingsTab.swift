import SwiftUI

import SiriusKit

struct AboutSettingsTab: View {
    @Environment(\.openURL)
    private var openURL

    var body: some View {
        Form {
            Section {
                SettingsEntry(title: String(localized: "settings.about.server_version.title", defaultValue: "Noctiluca Server 버전")) {
                    VStack(alignment: .trailing) {
                        Text(NoctilucaMeta.version)
#if DEBUG
                        Text(markdown: String(localized: "settings.about.server_version.development", defaultValue: "개발 버전"))
                            .font(.subheadline)
#else
                        Text(markdown: String(localized: "settings.about.server_version.release", defaultValue: "릴리즈 버전"))
                            .font(.subheadline)
#endif
                    }
                }
                SettingsEntry(title: String(localized: "settings.about.siriuskit_version.title", defaultValue: "SiriusKit 버전")) {
                    VStack(alignment: .trailing) {
                        Text("\(SiriusKitMeta.displayVersion)")
                        Text(markdown: String(localized: "settings.about.siriuskit_version.protocol_version", defaultValue: "프로토콜 버전 \(SiriusKitMeta.currentProtocolVersion.displayVersion)"))
                            .font(.subheadline)
                    }
                }
                SettingsEntry(title: String(localized: "settings.about.transport_layer.title", defaultValue: "사용 가능한 트랜스포트 레이어 구현체")) {
                    VStack(alignment: .trailing) {
                        ForEach(TransportLayerImplementation.bundledImplementations, id: \.self) { implementation in
                            Text(implementation.displayName)
                        }
                    }
                }
                SettingsEntry(title: String(localized: "settings.about.features.title", defaultValue: "사용 가능한 기능 목록")) {
                    VStack(alignment: .trailing) {
                        Text("HIDIO")
                        Text("Projection")
                        Text("ProjectionData")
                    }
                }
            } header: {
                Text(markdown: String(localized: "settings.about.header.title", defaultValue: "Noctiluca Server 정보"))
                Text("")
            } footer: {
                Text(markdown: String(localized: "settings.about.footer.oss_notice", defaultValue: "이 소프트웨어는 오픈 소스 소프트웨어가 포함되어 있습니다. [라이선스 정보…](https://noctiluca.app/docs/open-sources/server)"))
                // Text(markdown: String(localized: "settings.about.footer.sirius_protocol", defaultValue: "Sirius 프로토콜의 사양 문서는 GitHub [team-unstablers/SiriusProtocol](https://github.com/team-unstablers/SiriusProtocol) 에 공개되어 있습니다."))
                Text("")
                Text(markdown: String(localized: "settings.about.footer.copyright", defaultValue: "© 2026 team unstablers Inc."))
                Text(markdown: String(localized: "settings.about.footer.legal_links", defaultValue: "[GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.html) • [개인정보처리방침](https://noctiluca.app/docs/privacy-policy)"))
            }
        }
        .formStyle(.grouped)
    }
}

