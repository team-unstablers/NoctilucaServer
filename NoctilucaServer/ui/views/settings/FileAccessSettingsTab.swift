//
//  FileAccessSettingsTab.swift
//  NoctilucaServer
//

import SwiftUI
import Inject

import SiriusKit

struct FileAccessSettingsTab: View {
    @ObserveInjection
    var inject

    @Binding
    var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.fileAccess.enabled) {
                    Text(markdown: String(
                        localized: "settings.file_access.enabled.title",
                        defaultValue: "원격 파일 시스템 마운트 사용하기"
                    ))
                    Text(markdown: String(
                        localized: "settings.file_access.enabled.description",
                        defaultValue: "이 옵션을 켜면 connect 해 온 클라이언트(navigator)가 노출하는 폴더를 호스트 머신의 Finder에 NFS 마운트 형태로 띄울 수 있게 됩니다. 자기 파일을 *내보내는* 기능이 아니라, 원격에서 받은 파일을 *받아서 마운트* 하는 기능입니다."
                    ))
                }
            } header: {
                Text(markdown: String(
                    localized: "settings.file_access.section_general.title",
                    defaultValue: "일반"
                ))
                Text(markdown: String(
                    localized: "settings.file_access.section_general.description",
                    defaultValue: "원격 파일 시스템 마운트 (fsaccess) 의 호스트 측 정책을 설정합니다."
                ))
            }

            Section {
                TextField(
                    text: $settings.fileAccess.mountPointPath,
                    prompt: Text(verbatim: "~/NoctilucaFS")
                ) {
                    Text(markdown: String(
                        localized: "settings.file_access.mount_point.title",
                        defaultValue: "마운트 위치"
                    ))
                    Text(markdown: String(
                        localized: "settings.file_access.mount_point.description",
                        defaultValue: "원격 파일이 보일 호스트 머신의 디렉토리. 비어있는 디렉토리이거나 존재하지 않는 경로여야 합니다. 변경하면 다음 서버 시작 시 적용됩니다."
                    ))
                }
                .disabled(!settings.fileAccess.enabled)
            } header: {
                Text(markdown: String(
                    localized: "settings.file_access.section_mount.title",
                    defaultValue: "마운트 위치"
                ))
            }

            Section {
                Picker(selection: $settings.fileAccess.defaultConsentPolicy) {
                    Text(String(
                        localized: "settings.file_access.consent.always_ask",
                        defaultValue: "매번 묻기"
                    ))
                    .tag(HostFSAccessConsentPolicy.alwaysAsk)

                    Text(String(
                        localized: "settings.file_access.consent.always_allow",
                        defaultValue: "전부 자동 마운트 (읽기/쓰기)"
                    ))
                    .tag(HostFSAccessConsentPolicy.alwaysAllow)

                    Text(String(
                        localized: "settings.file_access.consent.always_allow_read_only",
                        defaultValue: "전부 자동 마운트 (읽기 전용)"
                    ))
                    .tag(HostFSAccessConsentPolicy.alwaysAllowReadOnly)

                    Text(String(
                        localized: "settings.file_access.consent.deny",
                        defaultValue: "거부 (control channel 자체를 안 엶)"
                    ))
                    .tag(HostFSAccessConsentPolicy.deny)
                } label: {
                    Text(markdown: String(
                        localized: "settings.file_access.consent.title",
                        defaultValue: "기본 마운트 정책"
                    ))
                    Text(markdown: String(
                        localized: "settings.file_access.consent.description",
                        defaultValue: "navigator 가 List 응답으로 알려준 entries 를 어떻게 처리할지의 기본값입니다. 개별 connection 별 예외 정책 (allowedConnections) 은 향후 추가 예정입니다."
                    ))
                }
                .disabled(!settings.fileAccess.enabled)
            } header: {
                Text(markdown: String(
                    localized: "settings.file_access.section_consent.title",
                    defaultValue: "Mount 트리거 정책"
                ))
                Text(markdown: String(
                    localized: "settings.file_access.section_consent.description",
                    defaultValue: "어떤 navigator entry 를 자동 마운트할지의 호스트 측 정책. **navigator 측의 사용자 동의 prompt 와는 별개** 입니다 — navigator 측 prompt 는 navigator 사용자가 자기 파일을 누구에게 보여줄지 결정하는 것이고, 본 정책은 host 사용자가 받은 entries 를 자기 머신에 마운트할지 결정하는 것입니다."
                ))
            }
        }
        .formStyle(.grouped)
        .enableInjection()
    }
}
