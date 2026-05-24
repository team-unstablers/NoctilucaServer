//
//  MiscSettingsTab.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import SwiftUI

struct MiscSettingsTab: View {
    @Binding
    var settings: AppSettings

    var body: some View {
        Form {
            Section {
                Toggle(isOn: .constant(true)) {
                    Text(markdown: String(localized: "settings.misc.hidio_qos.title", defaultValue: "HIDIO 채널에 높은 QoS 우선순위 적용하기"))
                    Text(markdown: String(localized: "settings.misc.hidio_qos.description", defaultValue: "MsQuic 스케줄러에게 HIDIO 채널과 관련된 스트림에 대해 높은 QoS 우선순위를 적용하도록 요청하여, 낮은 스루풋 환경에서도 입력 지연을 최소화 하기 위해 노력합니다."))
                }
                .disabled(true)
                
                Toggle(isOn: $settings.misc.showPerformanceOverlay) {
                    Text(markdown: String(localized: "settings.misc.performance_overlay.title", defaultValue: "디버그용 통계 정보 표시하기"))
                    Text(markdown: String(localized: "settings.misc.performance_overlay.description", defaultValue: "디버그용 통계 정보를 표시합니다."))
                }

                Toggle(isOn: $settings.misc.showDebugWindow) {
                    Text(markdown: String(localized: "settings.misc.debug_window.title", defaultValue: "세션 디버그 윈도우 표시하기"))
                    Text(markdown: String(localized: "settings.misc.debug_window.description", defaultValue: "각 세션의 채널, 프로젝션, 입력 상태를 실시간으로 확인할 수 있는 디버그 윈도우를 표시합니다."))
                }

                Toggle(isOn: $settings.misc.showAppStreamWindowInfoOverlay) {
                    Text(markdown: String(localized: "settings.misc.appstream_window_info_overlay.title", defaultValue: "AppStream 윈도우에 디버그 인디케이터 표시하기"))
                    Text(markdown: String(localized: "settings.misc.appstream_window_info_overlay.description", defaultValue: "AppStream으로 띄워진 각 윈도우 우상단에 원격 윈도우의 ID, 역할, bounds 등 디버그 정보를 표시합니다."))
                }
            } header: {
                Text(markdown: String(localized: "settings.misc.experimental.header", defaultValue: "실험 기능"))
            }
        }
        .formStyle(.grouped)
    }
}
