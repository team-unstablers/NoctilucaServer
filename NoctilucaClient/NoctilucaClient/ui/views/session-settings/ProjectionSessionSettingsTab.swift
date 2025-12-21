import SwiftUI

struct ProjectionSessionSettingsTab: View {
    @State
    var codecSpecifications: [CodecSpecification] = [
        .hevc
    ]
    
    var body: some View {
        Form {
            Section {
                SettingsPicker(selection: .constant("use-default")) {
                    SettingsPickerItem(value: "use-default") {
                        Text("권장 설정 사용 **(권장)**")
                        Text("Noctiluca Navigator에서 미리 정의된 코덱 설정을 사용합니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    SettingsPickerItem(value: "manual") {
                        Text("직접 설정 (고급)")
                        Text("사용자가 직접 코덱 요구사항을 설정합니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("코덱 설정 모드")
                    Text("코덱 설정 모드를 선택합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("코덱 설정")
            }
            
            Section {
                SettingsPicker(selection: .constant("as-optional")) {
                    SettingsPickerItem(value: "as-optional") {
                        Text("호환성 우선 **(권장)**")
                        Text("사용자가 지정한 코덱 관련 요구 사항을 전부 필수적이지 않은 것으로 마킹합니다.\n유연하게 협상이 가능하지만 요구 사항이 전부 충족되지 않을 수도 있습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    SettingsPickerItem(value: "as-mandatory") {
                        Text("요구 사항 우선")
                        Text("사용자가 지정한 코덱 관련 요구 사항을 전부 필수적인 것으로 마킹합니다.\n서버가 요구 사항을 충족하지 못할 경우 협상에 실패할 수 있습니다.\n또한, 서버 측의 코덱 협상 정책에 따라 요구 사항이 무시될 수도 있습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("코덱 협상 정책")
                    Text("서버와의 코덱 협상 정책을 설정합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            Section {
                CodecSpecificationListContainer(codecSpecifications: $codecSpecifications)
            }
        }
        .formStyle(.grouped)
    }
}
