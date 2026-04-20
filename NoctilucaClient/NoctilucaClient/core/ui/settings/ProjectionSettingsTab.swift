import SwiftUI

#if os(iOS)
import UIKit
#endif

struct ProjectionSettingsTab: View {
    @EnvironmentObject
    private var settingsStore: SettingsStore

#if os(iOS)
    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }
#endif

    var body: some View {
        Form {
            Section {
                SettingsPicker(selection: $settingsStore.settings.projection.enableJitterBuffer) {
                    SettingsPickerItem(value: false) {
                        Text(markdown: String(localized: "settings.projection.video_policy.fast.title", defaultValue: "최대한 빠르게 표시하기"))
                        Text(markdown: String(localized: "settings.projection.video_policy.fast.description", defaultValue: "화면 데이터가 도착하는 대로 최대한 빠르게 표시합니다.\n딜레이는 적지만, 네트워크 지터(Jitter)로 인하여 약간의 불쾌감이 들 수 있습니다."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    SettingsPickerItem(value: true) {
                        Text(markdown: String(localized: "settings.projection.video_policy.jitter_buffer.title", defaultValue: "지터 버퍼 사용하기"))
                        Text(markdown: String(localized: "settings.projection.video_policy.jitter_buffer.description", defaultValue: "화면 데이터를 조금씩 모아두었다가 일정한 간격으로 재생하려 노력합니다.\n화면 표시 딜레이가 조금 늘어납니다."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text(markdown: String(localized: "settings.projection.video_policy.title", defaultValue: "화면 프로젝션 정책"))
                    Text(markdown: String(localized: "settings.projection.video_policy.description", defaultValue: "화면 프로젝션과 관련된 정책을 설정합니다."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if settingsStore.settings.projection.enableJitterBuffer {
                    SettingsPicker(selection: $settingsStore.settings.projection.jitterBufferPreset) {
                        ForEach(AppSettings.JitterBufferPreset.allCases, id: \.self) { preset in
                            SettingsPickerItem(value: preset) {
                                Text(preset.displayName)
                                Text(preset.description)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } label: {
                        Text(markdown: String(localized: "settings.projection.jitter_buffer_preset.title", defaultValue: "지터 버퍼 프리셋"))
                        Text(markdown: String(localized: "settings.projection.jitter_buffer_preset.description", defaultValue: "지터 버퍼의 지연 시간과 안정성 사이의 균형을 조절합니다."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(markdown: String(localized: "settings.projection.advanced.header", defaultValue: "고급 설정"))
                Text(markdown: String(localized: "settings.projection.advanced.description", defaultValue: "프로젝션과 관련된 고급 설정을 구성합니다."))
            }
            
            Section {
                SettingsPicker(selection: $settingsStore.settings.projection.rendererImplementation) {
                    ForEach(AppSettings.RendererImplementation.allCases, id: \.self) { impl in
                        SettingsPickerItem(value: impl) {
                            Text(markdown: impl.displayName)
                            Text(markdown: impl.description)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                } label: {
                    Text(markdown: String(localized: "settings.projection.renderer_implementation.title", defaultValue: "화면 렌더러 구현체"))
                    Text(markdown: String(localized: "settings.projection.renderer_implementation.description", defaultValue: "화면 렌더러 구현체를 선택합니다."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Toggle(isOn: $settingsStore.settings.projection.casEnabled) {
                    Text(String(localized: "settings.projection.cas.toggle.title", defaultValue: "선명도 필터 (CAS)"))
                    Text(String(localized: "settings.projection.cas.toggle.description", defaultValue: "Contrast Adaptive Sharpening 필터를 적용합니다.\n원격 화면의 텍스트나 경계를 더 선명하게 표시합니다."))
                }
                .disabled(settingsStore.settings.projection.rendererImplementation != .nocMetalVideoRenderer)

                if settingsStore.settings.projection.casEnabled {
                    SettingsEntry(
                        title: String(localized: "settings.projection.cas.sharpness.title", defaultValue: "필터 세기"),
                        subtitle: String(format: "%.2f", settingsStore.settings.projection.casSharpness)
                    ) {
                        Slider(value: $settingsStore.settings.projection.casSharpness, in: 0.0...1.0, step: 0.1) {
                            EmptyView()
                        } minimumValueLabel: {
                            Text("0")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Text("1")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(String(localized: "settings.projection.rendering.header", defaultValue: "화면 렌더링"))
            }

            Section {
                SettingsPicker(selection: $settingsStore.settings.projection.audioProjectionPolicy) {
                    SettingsPickerItem(value: AppSettings.AudioProjectionPolicy.latencyFirst) {
                        Text(markdown: String(localized: "settings.projection.audio_policy.latency_first.title", defaultValue: "낮은 지연 시간을 우선하기"))
                        Text(markdown: String(localized: "settings.projection.audio_policy.latency_first.description", defaultValue: "지연 시간을 최대한 줄이도록 코덱을 구성하고, 오디오의 지터 버퍼를 최대한 작게 잡습니다.\n조금이라도 타이밍을 놓칠 것 같으면, 오디오 프레임을 적극적으로 건너뜁니다."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    SettingsPickerItem(value: AppSettings.AudioProjectionPolicy.stabilityFirst) {
                        Text(markdown: String(localized: "settings.projection.audio_policy.stability_first.title", defaultValue: "안정성을 우선하기"))
                        Text(markdown: String(localized: "settings.projection.audio_policy.stability_first.description", defaultValue: "품질을 우선하도록 코덱을 구성하고, 오디오의 지터 버퍼를 적절한 크기로 유지합니다.\n네트워크 상태가 불안정한 경우에도 오디오 끊김 현상을 최소화합니다."))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    Text(markdown: String(localized: "settings.projection.audio_policy.title", defaultValue: "오디오 프로젝션 정책"))
                    Text(markdown: String(localized: "settings.projection.audio_policy.description", defaultValue: "오디오 프로젝션의 동작과 관련된 정책을 설정합니다."))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

#if os(iOS)
            if isIPad {
                Section {
                    Toggle(isOn: $settingsStore.settings.projection.allowSubDisplayWindow) {
                        Text(String(localized: "settings.projection.allow_sub_display_window.title", defaultValue: "원격 디스플레이를 별도 윈도우로 분리할 수 있게 하기"))
                        Text(String(localized: "settings.projection.allow_sub_display_window.description", defaultValue: "디스플레이 선택 시트에서 각 원격 디스플레이를 iPad의 별도 윈도우(UIWindowScene)로 분리할 수 있게 합니다.\niPad Pro에서 외부 디스플레이를 연결하여 다중 디스플레이처럼 사용하려는 경우에 유용합니다."))
                    }
                } header: {
                    Text(String(localized: "settings.projection.multi_display.header", defaultValue: "멀티 디스플레이"))
                }
            }
#endif

        }
        .formStyle(.grouped)
        .navigationTitle(String(localized: "settings.projection.navigation_title", defaultValue: "프로젝션 설정"))
    }
}

#Preview {
    ProjectionSettingsTab()
        .frame(minHeight: 720)
        .environmentObject(SettingsStore.shared)
}
