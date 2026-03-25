import SwiftUI
import Inject

import SiriusKit

struct TransferSettingsTab: View {
    @ObserveInjection
    var inject

    @Binding
    var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.clipboard.enabled) {
                    Text(markdown: String(localized: "settings.transfer.clipboard.enabled.title", defaultValue: "클립보드 공유 사용하기"))
                    Text(markdown: String(localized: "settings.transfer.clipboard.enabled.description", defaultValue: "클립보드 공유 기능을 사용할지 여부를 설정합니다. 이 기능이 활성화된 경우, 클라이언트와 서버 간에 클립보드 데이터를 주고받을 수 있습니다."))
                }

                Picker(selection: $settings.clipboard.syncDirection) {
                    Text(String(localized: "settings.transfer.clipboard.sync_direction.local_to_remote", defaultValue: "서버 → 클라이언트만"))
                        .tag(ClipboardSyncDirection.localToRemote)

                    Text(String(localized: "settings.transfer.clipboard.sync_direction.remote_to_local", defaultValue: "클라이언트 → 서버만"))
                        .tag(ClipboardSyncDirection.remoteToLocal)

                    Text(String(localized: "settings.transfer.clipboard.sync_direction.bidirectional", defaultValue: "양방향"))
                        .tag(ClipboardSyncDirection.bidirectional)
                } label: {
                    Text(markdown: String(localized: "settings.transfer.clipboard.sync_direction.title", defaultValue: "클립보드 공유 방향"))
                }

                Toggle(isOn: $settings.clipboard.textOnly) {
                    Text(markdown: String(localized: "settings.transfer.clipboard.text_only.title", defaultValue: "텍스트만 허용하기"))
                    Text(markdown: String(localized: "settings.transfer.clipboard.text_only.description", defaultValue: "텍스트 데이터를 제외한 클립보드 데이터를 공유할지 여부를 설정합니다. 이 옵션이 활성화된 경우, 클립보드 공유 기능은 텍스트 데이터에 대해서만 동작하게 되며, 아래의 다른 클립보드 데이터 공유를 허용하는 옵션은 자동으로 비활성화됩니다."))
                }

                if !settings.clipboard.textOnly {
                    Toggle(isOn: $settings.clipboard.allowImage) {
                        Text(markdown: String(localized: "settings.transfer.clipboard.allow_image.title", defaultValue: "이미지 복사 허용하기"))
                        Text(markdown: String(localized: "settings.transfer.clipboard.allow_image.description", defaultValue: "이미지 데이터를 클립보드를 통해 공유하는 것을 허용할지 여부를 설정합니다."))
                    }

                    Toggle(isOn: $settings.clipboard.allowRichText) {
                        Text(markdown: String(localized: "settings.transfer.clipboard.allow_rich_text.title", defaultValue: "리치 텍스트 / HTML 복사 허용하기"))
                        Text(markdown: String(localized: "settings.transfer.clipboard.allow_rich_text.description", defaultValue: "리치 텍스트 또는 HTML 형식의 데이터를 클립보드를 통해 공유하는 것을 허용할지 여부를 설정합니다."))
                    }

                    Toggle(isOn: $settings.clipboard.allowUnknownFormat) {
                        Text(markdown: String(localized: "settings.transfer.clipboard.allow_unknown_format.title", defaultValue: "잘 알려지지 않은 형식의 데이터 복사 허용하기"))
                        Text(markdown: String(localized: "settings.transfer.clipboard.allow_unknown_format.description", defaultValue: "텍스트, 이미지, 리치 텍스트/HTML 이외의 형식으로 된 데이터를 클립보드를 통해 공유하는 것을 허용할지 여부를 설정합니다."))
                    }

                    Toggle(isOn: $settings.clipboard.allowFile) {
                        Text(markdown: String(localized: "settings.transfer.clipboard.allow_file.title", defaultValue: "파일 복사 허용하기"))
                        Text(markdown: String(localized: "settings.transfer.clipboard.allow_file.description", defaultValue: "⌘C / ⌘V와 같은 클립보드 복사/붙여넣기 동작을 통해 파일을 복사하는 것을 허용할지 여부를 설정합니다."))
                    }
                }
            } header: {
                Text(markdown: String(localized: "settings.transfer.clipboard.section_title", defaultValue: "클립보드 채널"))
                Text(markdown: String(localized: "settings.transfer.clipboard.section_description", defaultValue: "클립보드 공유 관련 정책을 설정합니다."))
            } footer: {
                Text(markdown: String(localized: "settings.transfer.clipboard.footer", defaultValue: "**참고**: 파일 복사 및 128KB 이상의 클립보드 데이터는 Transfer 채널을 통해 전송됩니다."))
            }

            Section {
                Toggle(isOn: $settings.transfer.enableCompression) {
                    Text(markdown: String(localized: "settings.transfer.channel.compression.title", defaultValue: "가능한 경우 압축 사용하기"))
                    Text(markdown: String(localized: "settings.transfer.channel.compression.description", defaultValue: "Zstd 압축을 사용할지 여부를 설정합니다.\n데이터 전송량이 줄어들 수 있지만, 컴퓨팅 자원 사용량이 늘어날 수 있습니다."))
                }
            } header: {
                Text(markdown: String(localized: "settings.transfer.channel.section_title", defaultValue: "Transfer 채널"))
                Text(markdown: String(localized: "settings.transfer.channel.section_description", defaultValue: "데이터 전송을 위한 Transfer 채널 관련 정책을 설정합니다."))
            }

            /*
            Section {
                IntegerField(value: .constant(64)) {
                    Text("데이터 블록 크기")
                    Text("데이터를 전송할 때 사용하는 블록의 크기 (KB 단위)를 설정합니다.")
                }
            } header: {
                Text("고급 사용자용 설정")
            }
             */
        }
        .formStyle(.grouped)
        .enableInjection()
    }
}
