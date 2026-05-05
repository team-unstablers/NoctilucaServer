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
                SettingsPicker(selection: $sessionSettings.transfer.fsAccessPolicy) {
                    SettingsPickerItem(value: SessionSettings.FSAccessPolicy.alwaysAllow) {
                        Text(markdown: String(localized: "session-settings.transfer.fs_access.policy.always_allow", defaultValue: "항상 허용 **(위험!)**"))
                        Text(markdown: String(localized: "session-settings.transfer.fs_access.policy.always_allow_desc", defaultValue: "확인 없이 모든 파일 시스템 접근 요청을 허용합니다. 신뢰할 수 있는 환경에서만 사용하세요."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    SettingsPickerItem(value: SessionSettings.FSAccessPolicy.alwaysAllowReadOnly) {
                        Text(markdown: String(localized: "session-settings.transfer.fs_access.policy.always_allow_ro", defaultValue: "항상 읽기 전용으로 허용"))
                        Text(markdown: String(localized: "session-settings.transfer.fs_access.policy.always_allow_ro_desc", defaultValue: "모든 접근 요청을 읽기 전용으로 강제하여 허용합니다. 아래 목록의 권한이 '읽기/쓰기'여도 읽기 전용으로 다운그레이드됩니다."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    SettingsPickerItem(value: SessionSettings.FSAccessPolicy.alwaysAsk) {
                        Text(markdown: String(localized: "session-settings.transfer.fs_access.policy.always_ask", defaultValue: "항상 묻기 **(권장)**"))
                        Text(markdown: String(localized: "session-settings.transfer.fs_access.policy.always_ask_desc", defaultValue: "서버에서 접근 요청이 있을 때마다 사용자에게 확인을 받습니다."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    SettingsPickerItem(value: SessionSettings.FSAccessPolicy.deny) {
                        Text(markdown: String(localized: "session-settings.transfer.fs_access.policy.deny", defaultValue: "거부하기"))
                        Text(markdown: String(localized: "session-settings.transfer.fs_access.policy.deny_desc", defaultValue: "모든 파일 시스템 접근 요청을 거부합니다."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text(markdown: String(localized: "session-settings.transfer.fs_access.policy.title", defaultValue: "파일 시스템 액세스 허용하기"))
                    Text(markdown: String(localized: "session-settings.transfer.fs_access.policy.description", defaultValue: "서버가 이 기기의 파일 시스템에 접근하려 할 때의 정책을 설정합니다."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

#if os(macOS)
                if sessionSettings.transfer.fsAccessPolicy != .deny {
                    FSAllowedEntriesListContainer(entries: $sessionSettings.transfer.fsAllowedEntries)
                }
#elseif os(iOS)
                if sessionSettings.transfer.fsAccessPolicy != .deny {
                    Toggle(isOn: $sessionSettings.transfer.fsExposeIOSDocuments) {
                        Text(markdown: String(localized: "session-settings.transfer.fs_access.ios.expose_documents.title", defaultValue: "이 기기의 파일 노출하기"))
                        Text(markdown: String(localized: "session-settings.transfer.fs_access.ios.expose_documents.description", defaultValue: "**파일** 앱의 `Noctiluca Navigator/fsaccess/` 폴더를 원격 호스트에 노출합니다. 사용자는 해당 폴더에 파일을 직접 넣고 뺄 수 있습니다."))
                    }

                    if sessionSettings.transfer.fsExposeIOSDocuments {
                        SettingsPicker(selection: $sessionSettings.transfer.fsIOSDocumentsACL) {
                            SettingsPickerItem(value: SessionSettings.FSAccessACL.readOnly) {
                                Text(markdown: String(localized: "session-settings.transfer.fs_access.acl.read_only", defaultValue: "읽기 전용"))
                            }

                            SettingsPickerItem(value: SessionSettings.FSAccessACL.readWrite) {
                                Text(markdown: String(localized: "session-settings.transfer.fs_access.acl.read_write", defaultValue: "읽기/쓰기"))
                            }
                        } label: {
                            Text(markdown: String(localized: "session-settings.transfer.fs_access.ios.acl.title", defaultValue: "원격 호스트의 권한"))
                            Text(markdown: String(localized: "session-settings.transfer.fs_access.ios.acl.description", defaultValue: "원격 호스트가 이 폴더에 대해 가지는 권한을 설정합니다."))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
#endif
            } header: {
                Text(markdown: String(localized: "session-settings.transfer.fs_access.section_title", defaultValue: "파일 시스템 액세스"))
                Text(markdown: String(localized: "session-settings.transfer.fs_access.section_description", defaultValue: "원격 호스트에서 이 기기의 파일/디렉토리에 접근할 수 있도록 노출할 항목을 설정합니다."))
            } footer: {
#if os(iOS)
                Text(markdown: String(localized: "session-settings.transfer.fs_access.ios.section_footer", defaultValue: "**파일** 앱에서 *Noctiluca Navigator* 위치를 통해 `fsaccess/` 폴더에 접근할 수 있습니다. 노출하지 않을 파일은 다른 폴더에 보관하세요."))
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
