import SwiftUI

import SiriusKit

struct MiscSettingsTab: View {
    @Binding
    var settings: AppSettings

    var body: some View {
        Form {
            Section {
                SettingsPicker(selection: $settings.transport.implementation) {
                    SettingsPickerItem(value: TransportLayerImplementation.msQuic.identifier) {
                        Text(markdown: String(
                            localized: "settings.misc.transport_layer_implemenation.msquic.display_name",
                            defaultValue: "QUIC (MsQuic)"
                        ))
                        Text(markdown: String(
                            localized: "settings.misc.transport_layer_implemenation.msquic.description",
                            defaultValue: "오픈 소스 QUIC 구현체를 사용합니다."
                        ))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    SettingsPickerItem(value: TransportLayerImplementation.appleQuic.identifier) {
                        Text(markdown: String(
                            localized: "settings.misc.transport_layer_implemenation.apple_quic.display_name",
                            defaultValue: "QUIC (Network.framework) **(권장하지 않음)**"
                        ))
                        Text(markdown: String(
                            localized: "settings.misc.transport_layer_implemenation.apple_quic.description",
                            defaultValue: "macOS에서 기본으로 제공되는 Apple의 QUIC 구현체를 사용합니다.\n일부 기능이 제대로 동작하지 않거나, 낮은 성능을 낼 수 있습니다."
                        ))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("트랜스포트 레이어 구현체")
                    Text("서버 가동 시 사용할 트랜스포트 레이어 구현체를 선택합니다. 구현체에 따라 성능이나 세부 동작이 다를 수 있습니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text(markdown: String(localized: "settings.misc.transport_layer_misc.title", defaultValue: "기타 트랜스포트 레이어 설정"))
            } footer: {
                Text(markdown: String(
                    localized: "settings.misc.transport_layer_implementation.oss_notice",
                    defaultValue: "**오픈 소스 고지**: Noctiluca 제품군에서는 MsQuic에 다음과 같은 수정을 가하여 사용하고 있습니다:\n- Swift 언어에서 쉽게 사용할 수 있도록 [`swift-msquic`](https://github.com/team-unstablers/swift-msquic) 래퍼 모듈을 작성하였습니다.\n- iOS에서 [`dlopen(3)`](https://man.freebsd.org/cgi/man.cgi?dlopen(3))을 사용하지 않도록 수정하였습니다. 수정을 가한 포크 버전은 GitHub [team-unstablers/msquic](https://github.com/team-unstablers/msquic) 에 공개되어 있습니다."
                ))
            }
            
            Section(String(localized: "settings.misc.logging.title", defaultValue: "로깅")) {
                Toggle(isOn: $settings.logging.enableFileLogging) {
                    Text(markdown: String(localized: "settings.misc.logging.enable_file_logging.title",
                         defaultValue: "파일 로깅 활성화"))
                    Text(markdown: String(localized: "settings.misc.logging.enable_file_logging.description",
                         defaultValue: "로그를 ~/Library/Logs에 파일로 저장합니다."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Toggle(isOn: $settings.logging.enableLogRotation) {
                    Text(markdown: String(localized: "settings.misc.logging.enable_log_rotation.title",
                         defaultValue: "로그 로테이션 활성화"))
                    Text(markdown: String(localized: "settings.misc.logging.enable_log_rotation.description",
                         defaultValue: "로그 파일이 일정 크기를 초과하면 자동으로 새 파일로 전환합니다."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .disabled(!settings.logging.enableFileLogging)

                SettingsPicker(selection: $settings.logging.minimumLogLevel) {
                    SettingsPickerItem(value: "trace") { Text("Trace") }
                    SettingsPickerItem(value: "debug") { Text("Debug") }
                    SettingsPickerItem(value: "info") { Text("Info") }
                    SettingsPickerItem(value: "warning") { Text("Warning") }
                    SettingsPickerItem(value: "error") { Text("Error") }
                } label: {
                    Text(markdown: String(localized: "settings.misc.logging.minimum_log_level.title",
                         defaultValue: "최소 로그 레벨"))
                }

                SettingsEntry(
                    title: String(localized: "settings.misc.logging.max_file_size.title",
                           defaultValue: "최대 파일 크기 (MB)")
                ) {
                    TextField("", value: Binding(
                        get: { Int(settings.logging.maxFileSize / 1_048_576) },
                        set: { settings.logging.maxFileSize = UInt64(max($0, 1)) * 1_048_576 }
                    ), format: .number)
                    .frame(width: 80)
                    .textFieldStyle(.roundedBorder)
                }
                .disabled(!settings.logging.enableFileLogging || !settings.logging.enableLogRotation)

                SettingsEntry(
                    title: String(localized: "settings.misc.logging.max_file_count.title",
                           defaultValue: "최대 파일 수")
                ) {
                    Stepper(value: $settings.logging.maxFileCount, in: 1...100) {
                        Text("\(settings.logging.maxFileCount)")
                            .monospacedDigit()
                    }
                }
                .disabled(!settings.logging.enableFileLogging || !settings.logging.enableLogRotation)

                SettingsEntry(
                    title: String(localized: "settings.misc.logging.open_log_folder.title",
                           defaultValue: "로그 파일 위치")
                ) {
                    Button(String(localized: "settings.misc.logging.open_log_folder.action",
                           defaultValue: "Finder에서 열기")) {
                        NSWorkspace.shared.open(NoctilucaLoggingConfigurator.logDirectory)
                    }
                }
            }
            
            Section(String(localized: "settings.misc.telemetry.title", defaultValue: "텔레메트리 및 진단 정보")) {
                Toggle(isOn: $settings.telemetry.enableTelemetry) {
                    Text(markdown: String(localized: "settings.misc.telemetry.enable.title", defaultValue: "Noctiluca의 개발을 익명으로 돕기"))
                    Text(markdown: String(localized: "settings.misc.telemetry.enable.description", defaultValue: "사용자 환경 및 사용 통계를 익명으로 수집하는 것을 허용합니다.\n프라이버시 보호를 우선하기 위해, 이 옵션은 기본적으로 꺼져 있습니다. [더 알아보기…](http://google.com)"))
                }
                SettingsEntry(title: String(localized: "settings.misc.telemetry.identifier.title", defaultValue: "텔레메트리 식별자")) {
                    Button(String(localized: "settings.misc.telemetry.identifier.reset", defaultValue: "식별자 재설정")) {

                    }
                }

                SettingsEntry(title: String(localized: "settings.misc.diagnostics.export.title", defaultValue: "진단 정보 내보내기")) {
                    Button(String(localized: "settings.misc.diagnostics.export.save_to_file", defaultValue: "파일로 저장…")) {

                    }
                }
                SettingsEntry(title: String(localized: "settings.misc.connectivity_test.title", defaultValue: "외부 접속 테스트"), subtitle: String(localized: "settings.misc.connectivity_test.description", defaultValue: "주식회사 팀언스테이블러즈에서 제공하는 테스트 노드를 통해 외부로부터 접속이 가능한지 테스트합니다.")) {
                    Button(String(localized: "settings.misc.connectivity_test.request", defaultValue: "접속 테스트 요청하기")) {}
                }
            }
        }
        .formStyle(.grouped)
    }
}
