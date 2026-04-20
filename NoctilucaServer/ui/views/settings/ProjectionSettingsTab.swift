import SwiftUI

struct ProjectionSettingsTab: View {
    
    @Binding
    var settings: AppSettings
    
    var body: some View {
        Form {
            Section {
                Toggle(isOn: $settings.projection.allowModifyDisplayLayout) {
                    Text(markdown: String(localized: "settings.projection.allow_modify_display_layout.title", defaultValue: "디스플레이 레이아웃 변경을 허용하기"))
                    Text(markdown: String(localized: "settings.projection.allow_modify_display_layout.description", defaultValue: "클라이언트의 더 나은 원격 데스크톱 경험을 위해 Noctiluca Server가 호스트의 디스플레이 레이아웃을 변경하는 것을 허용합니다."))
                }

                Toggle(isOn: $settings.projection.allowVirtualDisplay) {
                    Text(markdown: String(localized: "settings.projection.allow_virtual_display.title", defaultValue: "가상 디스플레이 사용을 허용하기"))
                    Text(markdown: String(localized: "settings.projection.allow_virtual_display.description", defaultValue: "클라이언트의 더 나은 원격 데스크톱 경험을 위해 Noctiluca Server가 호스트에 가상 디스플레이를 추가하는 것을 허용합니다."))
                }
            } header: {
                Text(markdown: String(localized: "settings.projection.display.title", defaultValue: "디스플레이 설정"))
            } footer: {
                Text(markdown: String(localized: "settings.projection.display.description", defaultValue: "여러 클라이언트가 동시 접속되어 있는 경우, 이 설정은 그 중 첫번째 클라이언트에게만 유효합니다."))
            }
            
            Section {
                CodecNegotiationPolicyPicker(selection: $settings.projection.codecNegotiationPolicy)
                CodecSpecificationListContainer(codecSpecifications: $settings.projection.codecSpecifications)
            } header: {
                Text(markdown: String(localized: "settings.projection.video_encoder.title", defaultValue: "비디오 인코더 설정"))
            }
            
            Section {
                Toggle(String(localized: "settings.projection.audio.enable", defaultValue: "오디오 프로젝션 활성화"), isOn: $settings.projection.isAudioProjectionEnabled)
                
                if settings.projection.isAudioProjectionEnabled {
                    AudioCodecSpecificationListContainer(codecSpecifications: $settings.projection.audioCodecSpecifications)
                }
            } header: {
                Text(markdown: String(localized: "settings.projection.audio_encoder.title", defaultValue: "오디오 인코더 설정"))
            }
        }
        .formStyle(.grouped)
    }
}
