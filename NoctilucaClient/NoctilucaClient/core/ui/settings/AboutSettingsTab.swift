import SwiftUI

import SiriusKitClient

struct AboutSettingsTab: View {
    var body: some View {
        let productName = NoctilucaMeta.productName
        
        Form {
            Section {
                HStack(alignment: .top) {
                    VStack(alignment: .leading) {
                        Text(String(format: String(localized: "about.product_version.title_format", defaultValue: "%@ 버전"), productName))
                        Text("")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(String(format: String(localized: "about.version_full_format", defaultValue: "%@ (%@)"), NoctilucaMeta.version, NoctilucaMeta.buildVersion))
                        Text("App Store")
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                }
                HStack(alignment: .top) {
                    Text(markdown: String(localized: "about.siriuskit_version.title", defaultValue: "SiriusKit 버전"))
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(String(format: String(localized: "about.siriuskit_version.value_format", defaultValue: "%@ (%@)"), SiriusKitMeta.displayVersion, SiriusKitMeta.buildVersion))
                        Text(String(format: String(localized: "about.protocol_version_format", defaultValue: "프로토콜 버전 %@"), SiriusKitMeta.currentProtocolVersion.displayVersion))
                            .font(.subheadline)
                    }
                    .foregroundStyle(.secondary)
                }
                HStack(alignment: .top) {
                    Text(markdown: String(localized: "about.transport_layer.title", defaultValue: "사용 가능한 트랜스포트 레이어 구현체"))
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text(TransportLayerImplementation.msQuic.displayName)
                    }
                    .foregroundStyle(.secondary)
                }
                HStack(alignment: .top) {
                    Text(markdown: String(localized: "about.features.title", defaultValue: "사용 가능한 기능 목록"))
                    Spacer()
                    VStack(alignment: .trailing) {
                        Text("HIDIO")
                        Text("Projection")
                        Text("ProjectionData")
                    }
                    .foregroundStyle(.secondary)
                }
            } header: {
                Text(String(format: String(localized: "about.section_header_format", defaultValue: "%@ 정보"), productName))
            } footer: {
                Text(markdown: String(localized: "about.oss_license_info", defaultValue: "이 소프트웨어는 오픈 소스 소프트웨어가 포함되어 있습니다. [라이선스 정보…](https://noctiluca.app/docs/open-sources/navigator/apple)"))
                Text(markdown: String(localized: "about.sirius_protocol_spec", defaultValue: "Sirius 프로토콜의 사양 문서는 GitHub [team-unstablers/SiriusProtocol](https://github.com/team-unstablers/SiriusProtocol) 에 공개되어 있습니다."))
                Text("")
                Text("© 2025 team unstablers Inc. All rights reserved.")
            }
        }
        .formStyle(.grouped)
    }
}
