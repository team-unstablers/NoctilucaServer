//
//  FileAccessSettingsTab.swift
//  NoctilucaClient
//
//  fsaccess (파일시스템 공유) 의 navigator (이 client) 측 동작 토글.
//  현재는 iOS 전용 — macOS host 가 NFS client 로 접근할 때 자동 생성하는
//  AppleDouble sidecar 처리 정책을 사용자가 결정.
//

#if os(iOS)

import SwiftUI

struct FileAccessSettingsTab: View {
    @EnvironmentObject
    private var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settingsStore.settings.fileAccess.hideAppleDoubleFiles) {
                    Text(markdown: String(
                        localized: "settings.file_access.hide_apple_double.title",
                        defaultValue: "AppleDouble 파일을 노출하지 않기"
                    ))
                    Text(markdown: String(
                        localized: "settings.file_access.hide_apple_double.description",
                        defaultValue: "macOS 의 NFS 클라이언트는 비-HFS 볼륨에서 모든 파일 옆에 AppleDouble 파일 (`._<파일명>`) 을 자동으로 생성합니다. 이 기기의 저장소에 sidecar 가 누적되고 일부 앱 (특히 git) 이 오작동할 수 있습니다.\n\ngit 레포지토리 등 소프트웨어 개발 워크로드를 위해 이 기기의 파일시스템을 노출하려는 경우 이 옵션을 켜면 문제가 해결될 가능성이 있습니다.\n\n설정 변경은 다음 마운트 세션부터 적용됩니다."
                    ))
                }
            } header: {
                Text(markdown: String(
                    localized: "settings.file_access.workarounds.header",
                    defaultValue: "Workarounds"
                ))
            }
        }
        .formStyle(.grouped)
        .navigationTitle(String(
            localized: "settings.tabs.file_access",
            defaultValue: "파일 시스템 공유"
        ))
    }
}

#endif
