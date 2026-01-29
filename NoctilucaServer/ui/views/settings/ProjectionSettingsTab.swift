import SwiftUI

struct ProjectionSettingsTab: View {
    
    @Binding
    var settings: AppSettings
    
    var body: some View {
        Form {
            Section {
                ScreenRecorderPicker(selection: $settings.projection.preferredScreenRecorder)
            } header: {
                Text(markdown: String(localized: "settings.projection.screen_recorder.title", defaultValue: "화면 레코더 설정"))
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
