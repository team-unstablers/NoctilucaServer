import SwiftUI

struct ProjectionSettingsTab: View {
    @EnvironmentObject
    private var settingsStore: SettingsStore

    var body: some View {
        Form {
            Section {
                SettingsPicker(selection: .constant("auto")) {
                    SettingsPickerItem(value: "auto") {
                        Text("하드웨어 가속을 우선하기")
                        Text("가능한 경우 하드웨어 가속을 시도합니다.\n동시에 많은 비디오 스트림이 열려 있거나, 기기에서 지원하지 않는 형식의 비디오 스트림이 포함된 경우 소프트웨어 디코더로 폴백됩니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    SettingsPickerItem(value: "software") {
                        Text("소프트웨어 디코딩만 사용하기")
                        Text("항상 소프트웨어 방식의 디코더를 사용합니다.\n배터리 소모가 커질 수 있어 권장하지 않습니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("비디오 디코딩 정책")
                    Text("원격 세션의 화면 데이터를 압축 해제하는 방식을 설정합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("고급 설정")
                Text("프로젝션과 관련된 고급 설정을 구성합니다.")
            }
            
            Section {
                Toggle(isOn: .constant(false)) {
                    Text("오디오 프로젝션 사용하기")
                    Text("원격 세션의 오디오 스트림을 프로젝션 받도록 구성합니다.\n모든 서버 구현체가 이를 지원하는 것은 아닙니다.")
                }
                
                SettingsPicker(selection: .constant("latency-first")) {
                    SettingsPickerItem(value: "latency-first") {
                        Text("낮은 지연 시간을 우선하기")
                        Text("지연 시간을 최대한 줄이도록 코덱을 구성하고, 오디오의 지터 버퍼를 최대한 작게 잡습니다.\n조금이라도 타이밍을 놓칠 것 같으면, 오디오 프레임을 적극적으로 건너뜁니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    SettingsPickerItem(value: "stability-first") {
                        Text("안정성을 우선하기")
                        Text("품질을 우선하도록 코덱을 구성하고, 오디오의 지터 버퍼를 적절한 크기로 유지합니다.\n네트워크 상태가 불안정한 경우에도 오디오 끊김 현상을 최소화합니다.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text("오디오 프로젝션 정책")
                    Text("오디오 프로젝션의 동작과 관련된 정책을 설정합니다.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("실험 기능")
            }
            .disabled(true)

        }
        .formStyle(.grouped)
        .navigationTitle("프로젝션 설정")
    }
}

#Preview {
    ProjectionSettingsTab()
        .frame(minHeight: 720)
        .environmentObject(SettingsStore.shared)
}
