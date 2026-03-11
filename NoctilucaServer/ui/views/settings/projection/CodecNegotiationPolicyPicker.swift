//
//  CodecNegotiationPolicyPicker.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import SwiftUI

struct CodecNegotiationPolicyPicker: View {
    @Binding
    var selection: CodecNegotiationPolicy

    var body: some View {
        SettingsPicker(selection: $selection) {
            SettingsPickerItem(value: CodecNegotiationPolicy.balanced) {
                Text(markdown: String(localized: "settings.projection.negotiation_policy.balanced.title", defaultValue: "균형 잡힌 결정 내리기 **(권장)**"))
                Text(markdown: String(localized: "settings.projection.negotiation_policy.balanced.description", defaultValue: "클라이언트의 요청을 존중하면서 서버의 성능과 안정성을 해치지 않는 범위 내에서 최적의 코덱을 선택합니다.\n서버가 지원할 수 없는 명세의 코덱이 요청되었을 때에는 Noctiluca Server가 적절하다고 판단하는 코덱으로 임의 대체합니다."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            SettingsPickerItem(value: CodecNegotiationPolicy.overrideFromServer) {
                Text(markdown: String(localized: "settings.projection.negotiation_policy.override_from_server.title", defaultValue: "서버 설정을 우선으로"))
                Text(markdown: String(localized: "settings.projection.negotiation_policy.override_from_server.description", defaultValue: "클라이언트의 요청을 완전히 무시하고 서버의 코덱 설정을 우선시합니다.\n클라이언트가 지원하지 않는 코덱이 설정되어 있을 경우 연결에 실패할 수 있습니다."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text(markdown: String(localized: "settings.projection.negotiation_policy.title", defaultValue: "코덱 협상 정책"))
            Text(markdown: String(localized: "settings.projection.negotiation_policy.description", defaultValue: "클라이언트와의 코덱 협상 정책을 설정합니다."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}
