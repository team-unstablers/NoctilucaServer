//
//  MiscSettingsTab.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import SwiftUI

struct MiscSettingsTab: View {
    @EnvironmentObject
    private var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle(isOn: .constant(false)) {
                    Text("HIDIO 채널과 관련된 스트림에 높은 QoS 우선순위 적용하기")
                    Text("HIDIO 채널과 관련된 스트림에 대해 높은 QoS 우선순위를 적용하여, 낮은 스루풋 환경에서도 입력 지연을 최소화 하기 위해 노력합니다.\nApple의 Network.framework은 과도하게 일반화된 API를 제공하기 때문에, 이 설정이 실제로 효과가 있을지는 보장할 수 없습니다.")
                }
            } header: {
                Text("실험 기능")
            }
        }
        .formStyle(.grouped)
    }
}
