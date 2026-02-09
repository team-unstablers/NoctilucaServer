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
                    Text("HIDIO 채널에 높은 QoS 우선순위 적용하기")
                    Text("MsQuic 스케줄러에게 HIDIO 채널과 관련된 스트림에 대해 높은 QoS 우선순위를 적용하도록 요청하여, 낮은 스루풋 환경에서도 입력 지연을 최소화 하기 위해 노력합니다.")
                }
                .disabled(true)
                
                Toggle(isOn: $settings.misc.showPerformanceOverlay) {
                    Text("디버그용 통계 정보 표시하기")
                    Text("디버그용 통계 정보를 표시합니다.")
                }
            } header: {
                Text("실험 기능")
            }
        }
        .formStyle(.grouped)
    }
}
