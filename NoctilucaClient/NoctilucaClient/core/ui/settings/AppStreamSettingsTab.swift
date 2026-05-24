//
//  MiscSettingsTab.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import SwiftUI

#if os(macOS)
struct AppStreamSettingsTab: View {
    @Binding
    var settings: AppSettings
    
    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.misc.showAppStreamWindowInfoOverlay) {
                    Text(markdown: String(localized: "settings.misc.appstream_window_info_overlay.title", defaultValue: "AppStream 윈도우에 디버그 인디케이터 표시하기"))
                    Text(markdown: String(localized: "settings.misc.appstream_window_info_overlay.description", defaultValue: "AppStream으로 띄워진 각 윈도우 우상단에 원격 윈도우의 ID, 역할, bounds 등 디버그 정보를 표시합니다."))
                }
                
                /*
                Toggle(isOn: .constant(false)) {
                    Text(markdown: String(localized: "settings.appstream.use_vp8_on_small_window.title", defaultValue: "작은 크기의 윈도우에는 VP8 코덱을 사용하고, 프레임 레이트를 낮추기"))
                    Text(markdown: String(localized: "settings.appstream.use_vp8_on_small_window.description", defaultValue: "800x600 (480,000 픽셀) 이하의 윈도우에는 VP8 코덱을 사용합니다.\n여러 윈도우를 띄워야 하는 경우 도움이 될 수 있습니다."))
                }
                 */
            } header: {
                Text(markdown: String(localized: "settings.appstream.header", defaultValue: "AppStream (실험 단계)"))
            }
            
            /*
            Section {
                // $settings.appstream.quirks["app.noctiluca.appstream.quirks.use_a11y_context_menu"]
                Toggle(isOn: .constant(false)) {
                    Text(markdown: String(
                        localized: "settings.appstream.quirks.use_a11y_context_menu.title",
                        defaultValue: "a11y (접근성) 트리를 사용해 로컬에서 컨텍스트 메뉴 표시하기"
                    ))
                    Text(markdown: String(
                        localized: "settings.appstream.quirks.macos.use_a11y_context_menu.description",
                        defaultValue: "일부 버전의 macOS에서의 ScreenCaptureKit은, 가상 디스플레이에 있는 윈도우를 캡쳐하면 컨텍스트 메뉴는 캡쳐 내용에 포함되지 않는 문제가 있습니다.\n이를 해결하기 위해, 접근성 트리를 구독하고, 서버로부터 컨텍스트 메뉴에 대한 접근성 트리가 넘어오면 이를 대신 표시합니다.\n컨텍스트 메뉴가 여러 개 겹쳐 표시되는 경우, 이 플래그를 끄면 개선될 수도 있습니다."
                    ))
                }
                
            } header: {
                Text(markdown: String(localized: "settings.appstream.quirks.header.title", defaultValue: "호환성 플래그"))
                Text(markdown: String(localized: "settings.appstream.quirks.header.title", defaultValue: "AppStream은 기능의 특성상 호스트의 OS / 서버 소프트웨어에 따라 동작이 달라질 수 있습니다.\nNoctiluca에서는 그러함에도 최대한 동작의 정합성을 맞추기 위해 호환성 플래그 기능을 제공합니다."))
            }
            

            
            Section {
                // $settings.appstream.quirks["app.noctiluca.appstream.quirks.winman.geometry-sync-method"]
                SettingsPicker(selection: .constant("client-to-host")) {
                    SettingsPickerItem(value: "client-to-host") {
                        Text(markdown: String(
                            localized: "settings.appstream.quirks.winman.geometry-sync-method.client-to-host.title",
                            defaultValue: "단방향 (클라이언트 → 호스트)"
                        ))
                        Text(markdown: String(
                            localized: "settings.appstream.quirks.winman.geometry-sync-method.client-to-host.title",
                            defaultValue: "윈도우의 지오메트리 동기화를 단방향 (클라이언트 → 호스트)로만 수행합니다."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    SettingsPickerItem(value: "bidirectional-sync") {
                        Text(markdown: String(
                            localized: "settings.appstream.quirks.winman.geometry-sync-method.bidirectional-sync.title",
                            defaultValue: "양방향 동기화"
                        ))
                        Text(markdown: String(
                            localized: "settings.appstream.quirks.winman.geometry-sync-method.bidirectional-sync.title",
                            defaultValue: "윈도우의 지오메트리 동기화를 양방향으로 수행합니다. 윈도우를 이동할 때 윈도우가 떨릴 수 있습니다."
                        ))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                } label: {
                    Text(markdown: String(
                        localized: "settings.appstream.quirks.winman.geometry-sync-method.title",
                        defaultValue: "윈도우 지오메트리 동기화 방법"
                    ))
                    Text(markdown: String(
                        localized: "settings.appstream.quirks.winman.geometry-sync-method.description",
                        defaultValue: "윈도우 지오메트리 동기화 방법을 구성합니다."
                    ))
                }
            }
             */
            
        }
        .formStyle(.grouped)
    }
}
#endif
