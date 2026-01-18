import SwiftUI

struct ProjectionSettingsTab: View {
    
    @Binding
    var settings: AppSettings
    
    var body: some View {
        Form {
            Section {
                ScreenRecorderPicker()
            } header: {
                Text(String(localized: "settings.projection.screen_recorder.title", defaultValue: "화면 레코더 설정"))
            }
            Section {
                CodecNegotiationPolicyPicker()
                CodecSpecificationListContainer(codecSpecifications: $settings.projection.codecSpecifications)
            } header: {
                Text(String(localized: "settings.projection.video_encoder.title", defaultValue: "비디오 인코더 설정"))
            }
        }
        .formStyle(.grouped)
    }
}
