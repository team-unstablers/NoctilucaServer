import SwiftUI
import UniformTypeIdentifiers

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
                    Text(markdown: String(
                        localized: "settings.misc.transport_layer_implementation.title",
                        defaultValue: "트랜스포트 레이어 구현체"
                    ))
                    Text(markdown: String(
                        localized: "settings.misc.transport_layer_implementation.description",
                        defaultValue: "서버 가동 시 사용할 트랜스포트 레이어 구현체를 선택합니다. 구현체에 따라 성능이나 세부 동작이 다를 수 있습니다."
                    ))
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
            
            Section(String(localized: "settings.misc.logging.title", defaultValue: "이벤트 로깅")) {
                Toggle(isOn: $settings.logging.enableFileLogging) {
                    Text(markdown: String(localized: "settings.misc.logging.enable_file_logging.title",
                         defaultValue: "파일 로깅 활성화"))
                    Text(markdown: String(localized: "settings.misc.logging.enable_file_logging.description",
                         defaultValue: "접속/접속 해제 등 주요 이벤트를 ~/Library/Logs에 파일로 기록합니다."))
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

                SettingsEntry(
                    title: String(localized: "settings.misc.logging.max_file_size.title",
                           defaultValue: "최대 파일 크기 (MB)")
                ) {
                    TextField("", value: Binding(
                        get: { Int(settings.logging.maxFileSize / 1_048_576) },
                        set: { settings.logging.maxFileSize = UInt64(max($0, 1)) * 1_048_576 }
                    ), format: .number)
                    .frame(width: 80)
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
                    .frame(maxWidth: 60)
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
            
            Section {
                Toggle(isOn: $settings.telemetry.enableTelemetry) {
                    Text(markdown: String(localized: "settings.misc.telemetry.enable.title", defaultValue: "Noctiluca의 개발을 익명으로 돕기"))
                    Text(markdown: String(localized: "settings.misc.telemetry.enable.description", defaultValue: "Noctiluca Server가 가동 중 오류가 발생하거나, 비정상적으로 종료되었을 때 오류 보고를 익명으로 수집하는 것을 허용합니다.\n프라이버시 보호를 우선하기 위해, 이 옵션은 기본적으로 꺼져 있습니다. [더 알아보기…](https://noctiluca.app/docs/server/about-telemetry)"))
                }
                .onChange(of: settings.telemetry.enableTelemetry) { _, newValue in
                    if newValue {
                        settings.telemetry.ensureIdentifier()
                        TelemetryService.shared.startIfNeeded(settings: settings.telemetry)
                    } else {
                        TelemetryService.shared.stop()
                    }
                }

                SettingsEntry(
                    title: String(localized: "settings.misc.telemetry.identifier.title", defaultValue: "텔레메트리 식별자"),
                    subtitle: ((settings.telemetry.telemetryIdentifier?.uuidString ?? "(None)") + "\n\n" + String(localized: "settings.misc.telemetry.identifier.description", defaultValue: "이 텔레메트리 식별자는 UUIDv4 형식으로 생성된 것입니다. 사용자를 특정짓거나 추적하는 데 사용되지 않으며,\n단지 수집된 오류 보고 데이터가 서로 다른 사용자로부터 왔는지를 구분하는 데에만 사용됩니다."))
                ) {
                    Button(String(localized: "settings.misc.telemetry.identifier.reset", defaultValue: "식별자 재설정")) {
                        settings.telemetry.resetIdentifier()
                        TelemetryService.shared.restart(settings: settings.telemetry)
                    }
                }
                .disabled(!settings.telemetry.enableTelemetry)

                SettingsEntry(title: String(localized: "settings.misc.diagnostics.export.title", defaultValue: "진단 정보 내보내기")) {
                    Button(String(localized: "settings.misc.diagnostics.export.save_to_file", defaultValue: "파일로 저장…")) {
                        Task { await exportDiagnostics() }
                    }
                }
                SettingsEntry(title: String(localized: "settings.misc.connectivity_test.title", defaultValue: "외부 접속 테스트"), subtitle: String(localized: "settings.misc.connectivity_test.description", defaultValue: "주식회사 팀언스테이블러즈에서 제공하는 테스트 노드를 통해 외부로부터 접속이 가능한지 테스트합니다.")) {
                    Button(String(localized: "settings.misc.connectivity_test.request", defaultValue: "접속 테스트 요청하기")) {}
                }
            } header: {
                Text(String(localized: "settings.misc.telemetry.title", defaultValue: "텔레메트리 및 진단 정보"))
            } footer: {
                if !TelemetryService.shared.isAvailable {
                    Text(markdown: String(
                        localized: "settings.misc.telemetry.eea_notice",
                        defaultValue: "유럽경제지역(EEA) 또는 영국에 해당하는 지역 설정을 사용하고 있어 텔레메트리 기능을 활성화할 수 없습니다."
                    ))
                }
            }
            .disabled(!TelemetryService.shared.isAvailable)
        }
        .formStyle(.grouped)
    }

    @MainActor
    private func exportDiagnostics() async {
        var selectedLevel: DiagLevel?

        let alert = NOCAlert()
        alert.title = String(
            localized: "settings.misc.diagnostics.export.dialog.title",
            defaultValue: "어떻게 출력하시겠습니까?"
        )
        alert.message = String(
            localized: "settings.misc.diagnostics.export.dialog.message",
            defaultValue: """
            간단하게: GitHub 이슈 트래커나 남들이 볼 수 있는 곳에 진단 정보를 첨부하려는 경우에는 이 버튼을 클릭하십시오. \
            개인 식별이 가능하거나 민감한 정보는 최소한으로 노출을 줄입니다.

            상세하게: Noctiluca 개발자에게 직접 진단 정보를 전달하려는 경우에는 이 버튼을 클릭하십시오. \
            진단 내용에는 호스트네임, 네트워크 주소 등 개인 식별이 가능한 정보가 포함될 수 있습니다.
            """
        )

        alert.addButton(title: String(
            localized: "settings.misc.diagnostics.export.dialog.simple",
            defaultValue: "간단하게"
        )) {
            selectedLevel = .simple
        }
        alert.addButton(title: String(
            localized: "settings.misc.diagnostics.export.dialog.detailed",
            defaultValue: "상세하게"
        )) {
            selectedLevel = .detailed
        }

        await alert.present()

        guard let level = selectedLevel else { return }

        let text = await DiagPrinter().generate(level: level)

        let panel = NSSavePanel()
        panel.nameFieldStringValue = "noctiluca-diagnostics.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
