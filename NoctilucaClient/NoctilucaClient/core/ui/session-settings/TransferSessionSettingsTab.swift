import SwiftUI

struct TransferSessionSettingsTab: View {
    @Binding
    var sessionSettings: SessionSettings

    let scope: SessionSettingsScope

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $sessionSettings.clipboard.enabled) {
                    Text(markdown: String(localized: "session-settings.transfer.clipboard.enabled.title", defaultValue: "클립보드 공유 사용하기"))
                    Text(markdown: String(localized: "session-settings.transfer.clipboard.enabled.description", defaultValue: "클립보드 공유 기능을 사용할지 여부를 설정합니다. 이 기능이 활성화된 경우, 클라이언트와 서버 간에 클립보드 데이터를 주고받을 수 있습니다."))
                }

                Toggle(isOn: $sessionSettings.clipboard.textOnly) {
                    Text(markdown: String(localized: "session-settings.transfer.clipboard.text_only.title", defaultValue: "텍스트만 허용하기"))
                    Text(markdown: String(localized: "session-settings.transfer.clipboard.text_only.description", defaultValue: "텍스트 데이터를 제외한 클립보드 데이터를 송수신할지 여부를 설정합니다. 이 옵션이 활성화된 경우, 클립보드 공유 기능은 텍스트 데이터에 대해서만 동작하게 됩니다."))
                }

                if !sessionSettings.clipboard.textOnly {
                    Toggle(isOn: $sessionSettings.clipboard.allowFile) {
                        Text(markdown: String(localized: "session-settings.transfer.clipboard.allow_file.title", defaultValue: "파일 복사 허용하기 (실험적)"))
                        Text(markdown: String(localized: "session-settings.transfer.clipboard.allow_file.description", defaultValue: "⌘C / ⌘V와 같은 클립보드 복사/붙여넣기 동작을 통해 파일을 복사하는 것을 허용할지 여부를 설정합니다."))
                    }
                }

                Toggle(isOn: $sessionSettings.clipboard.useBidirectionalSync) {
                    Text(markdown: String(localized: "session-settings.transfer.clipboard.bidirectional_sync.title", defaultValue: "양방향 클립보드 동기화 사용하기"))
                    Text(markdown: String(localized: "session-settings.transfer.clipboard.bidirectional_sync.description", defaultValue: "로컬→원격 호스트로의 클립보드 동기화도 허용합니다."))
                }
            } header: {
                Text(markdown: String(localized: "session-settings.transfer.clipboard.section_title", defaultValue: "클립보드 채널"))
                Text(markdown: String(localized: "session-settings.transfer.clipboard.section_description", defaultValue: "클립보드 공유 관련 정책을 설정합니다."))
            } footer: {
#if os(iOS)
                Text(markdown: String(localized: "session-settings.transfer.clipboard.ios_file_warning", defaultValue: "**경고**: [iOS에서는 `NSFilePromiseProvider`같은 파일 공유를 위한 API가 존재하지 않아, 대신 `NSItemProvider`를 사용하고 있습니다.](https://www.google.com/search?q=NSFilePromiseProvider과+NSItemProvider의+차이는+무엇인가요%3F+왜+NSItemProvider를+통해+파일을+복사하면+곧바로+다운로드+되나요%3F+비전공자도+이해할+수+있도록+쉽게+알려주세요&udm=50) **현 구현에서는 원격 호스트에서 파일을 복사하면 곧바로 다운로드가 시작되는 문제가 있으며**, 해결 방안을 찾는 중입니다. 이로 인해 대량의 데이터가 예상치 못하게 다운로드될 수 있으므로 주의 바랍니다."))
#endif
            }

            Section {
                Toggle(isOn: $sessionSettings.transfer.enableCompression) {
                    Text(markdown: String(localized: "session-settings.transfer.channel.compression.title", defaultValue: "가능한 경우 압축 사용하기"))
                    Text(markdown: String(localized: "session-settings.transfer.channel.compression.description", defaultValue: "Zstd 압축을 사용할지 여부를 설정합니다.\n데이터 전송량이 줄어들 수 있지만, 컴퓨팅 자원 사용량이 늘어날 수 있습니다."))
                }
                .disabled(true)
            } header: {
                Text(markdown: String(localized: "session-settings.transfer.channel.section_title", defaultValue: "Transfer 채널"))
                Text(markdown: String(localized: "session-settings.transfer.channel.section_description", defaultValue: "데이터 전송을 위한 Transfer 채널 관련 정책을 설정합니다."))
            }
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SecuritySessionSettingsTab(
        sessionSettings: .constant(SessionSettings(scope: .global)),
        scope: .global,
        contactId: nil
    )
}
