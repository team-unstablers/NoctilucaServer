import SwiftUI

import SiriusKit

struct AboutSettingsTab: View {
    @Environment(\.openURL)
    private var openURL
    
    @State
    private var licenseState: LicenseValidationState = .unlicensed

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
                SettingsEntry(title: String(localized: "settings.about.license_status.title", defaultValue: "유효한 라이선스")) {
                    VStack(alignment: .trailing) {
                        switch licenseState {
                        case .valid:
                            Text(String(localized: "settings.about.license_status.valid", defaultValue: "예"))

                            HStack {
                                Button("라이선스 등록 해제") {
                                    removeLicense()
                                }
                            }
                        case .invalid:
                            Text(String(localized: "settings.about.license_status.invalid", defaultValue: "아니오"))

                            HStack {
                                Button("새 라이선스 등록") {
                                    (NSApp.delegate as? AppDelegate)?.showLicensingWindow(nil)
                                }

                                Button("Noctiluca Server 구매하기…") {
                                    openURL(URL(string: "https://noctiluca.app/pricing")!)
                                }
                            }
                        case .unlicensed:
                            Text(String(localized: "settings.about.license_status.unlicensed", defaultValue: "라이선스 없음"))

                            HStack {
                                Button("새 라이선스 등록") {
                                    (NSApp.delegate as? AppDelegate)?.showLicensingWindow(nil)
                                }

                                Button("Noctiluca Server 구매하기…") {
                                    openURL(URL(string: "https://noctiluca.app/pricing")!)
                                }
                            }
                        }
                    }
                }
            } header: {
                Text(markdown: String(localized: "settings.about.header.title", defaultValue: "Noctiluca Server 정보"))
                Text("")
            } footer: {
                Text(markdown: String(localized: "settings.about.footer.oss_notice", defaultValue: "이 소프트웨어는 오픈 소스 소프트웨어가 포함되어 있습니다. [라이선스 정보…](http://google.com)"))
                // Text(markdown: String(localized: "settings.about.footer.sirius_protocol", defaultValue: "Sirius 프로토콜의 사양 문서는 GitHub [team-unstablers/SiriusProtocol](https://github.com/team-unstablers/SiriusProtocol) 에 공개되어 있습니다."))
                Text("")
                Text(markdown: String(localized: "settings.about.footer.copyright", defaultValue: "© 2026 team unstablers Inc. All rights reserved."))
                Text("[Noctiluca Server 사용권 계약 (EULA)](https://noctiluca.app/docs/eula/server) • [개인정보처리방침](https://noctiluca.app/docs/privacy-policy)")
            }
        }
        .formStyle(.grouped)
        .task {
            licenseState = (await LicenseManager.shared.validationState) ?? .valid
        }
    }

    private func removeLicense() {
        Task {
            try? await LicenseManager.shared.removeLicense()
            licenseState = (await LicenseManager.shared.validationState) ?? .unlicensed
        }
    }
}

