//
//  CodecSpecificationSheet.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation

import SwiftUI

import SiriusKitClient

struct CodecSpecificationSheet: View {
    let onSave: (CodecSpecification) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State
    var specification: CodecSpecification

    init(specification: CodecSpecification, onSave: @escaping (CodecSpecification) -> Void) {
        _specification = State(initialValue: specification)
        self.onSave = onSave
    }

    // MARK: - Tab Views

    @ViewBuilder
    var basicSettingsView: some View {
        VStack {
            Form {
                qualityPolicySection()

                Section {
                    SettingsEntry(
                        title: String(localized: "session-settings.projection.codec.max_resolution", defaultValue: "최대 해상도"),
                        subtitle: specification.maximumResolutionLevel == .unlimited ? (
                            String(localized: "session-settings.projection.codec.max_resolution.auto_desc", defaultValue: "최대 해상도의 결정을 서버에게 맡깁니다.")
                        ) : (
                            String(format: String(localized: "session-settings.projection.codec.max_resolution.set_desc_format", defaultValue: "최대 해상도를 %@으로 제한합니다."), specification.maximumResolutionLevel.displayText)
                        )
                    ) {
                        Slider(
                            value: .convert($specification.maximumResolutionLevel.rawValue),
                            in: 0...Double(CodecResolutionLevel.hd4k.rawValue),
                            step: 1,
                            minimumValueLabel: Text(markdown: String(localized: "common.auto", defaultValue: "자동")),
                            maximumValueLabel: Text("4K")
                        ) {
                        }
                    }

                    Picker(selection: $specification.options[.displayDensity]) {
                        Text(markdown: String(localized: "common.auto", defaultValue: "자동"))
                            .tag(CodecOptionValue.kDisplayDensityAuto)

                        Text(markdown: String(localized: "session-settings.projection.codec.display_density.performance", defaultValue: "성능 우선"))
                            .tag(CodecOptionValue.kDisplayDensityPerformance)

                        Text(markdown: String(localized: "session-settings.projection.codec.display_density.best", defaultValue: "화질 우선"))
                            .tag(CodecOptionValue.kDisplayDensityBest)
                    } label: {
                        Text(markdown: String(localized: "session-settings.projection.codec.display_density", defaultValue: "디스플레이 밀도"))
                        switch specification.options[.displayDensity] {
                        case .kDisplayDensityAuto:
                            Text(markdown: String(localized: "session-settings.projection.codec.display_density.auto_desc", defaultValue: "디스플레이 밀도를 자동으로 선택합니다."))
                        case .kDisplayDensityPerformance:
                            Text(markdown: String(localized: "session-settings.projection.codec.display_density.performance_desc", defaultValue: "성능을 우선시하여 디스플레이 밀도를 설정합니다.\n대부분의 경우 1x 밀도로 설정됩니다."))
                        case .kDisplayDensityBest:
                            Text(markdown: String(localized: "session-settings.projection.codec.display_density.best_desc", defaultValue: "HIDPI / Retina 디스플레이 밀도를 사용하려 노력합니다.\n더 나은 화질을 제공하지만, 높은 대역폭과 컴퓨팅 자원을 사용합니다."))

                        default:
                            Text(markdown: String(localized: "session-settings.projection.codec.display_density.default_desc", defaultValue: "디스플레이 밀도를 설정합니다."))
                        }
                    }
                }

                Section {
                    SettingsEntry(
                        title: String(localized: "session-settings.projection.codec.frame_rate", defaultValue: "프레임 속도"),
                        subtitle: specification.frameRate == 0 ? (
                            String(localized: "session-settings.projection.codec.frame_rate.auto_desc", defaultValue: "최대 프레임 속도의 결정을 서버에게 맡깁니다.")
                        ) : (
                            String(format: String(localized: "session-settings.projection.codec.frame_rate.set_desc_format", defaultValue: "프레임 속도를 최대 %d FPS로 제한합니다."), Int(specification.frameRate))
                        )
                    ) {
                        Slider(
                            value: $specification.frameRate,
                            in: 0...60,
                            step: 15,
                            minimumValueLabel: Text(markdown: String(localized: "common.auto", defaultValue: "자동")),
                            maximumValueLabel: Text("60 FPS")
                        ) {
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    var detailsTab: some View {
        VStack {
            Form {
                Section {
                    Picker(selection: $specification.options[.hardwareAcceleration]) {
                        Text(markdown: String(localized: "common.auto", defaultValue: "자동"))
                            .tag(CodecOptionValue.kHardwareAccelerationAuto)
                        Text(markdown: String(localized: "session-settings.projection.codec.hw_accel.disabled", defaultValue: "사용 안 함"))
                            .tag(CodecOptionValue.kHardwareAccelerationFalse)
                    } label: {
                        Text(markdown: String(localized: "session-settings.projection.codec.hw_accel", defaultValue: "하드웨어 가속"))
                        switch specification.options[.hardwareAcceleration] {
                        case .kHardwareAccelerationAuto:
                            Text(markdown: String(localized: "session-settings.projection.codec.hw_accel.auto_desc", defaultValue: "서버가 환경에 맞춰 하드웨어 가속 사용 여부를 자동으로 결정합니다."))
                        case .kHardwareAccelerationFalse:
                            Text(markdown: String(localized: "session-settings.projection.codec.hw_accel.disabled_desc", defaultValue: "서버에게 하드웨어 가속 사용을 요청합니다.\n참고: 옵션 이름은 legacy 호환성 때문에 false로 표시됩니다."))
                        default:
                            Text(markdown: String(localized: "session-settings.projection.codec.hw_accel.default_desc", defaultValue: "서버 인코딩의 하드웨어 가속 요청 정책을 설정합니다."))
                        }
                    }

                    Picker(selection: $specification.options[.colorFormat]) {
                        Text(markdown: String(localized: "common.auto", defaultValue: "자동"))
                            .tag(CodecOptionValue.kColorFormatAuto)
                        Text("YUV 4:2:0")
                            .tag(CodecOptionValue.kColorFormatYUV420)
                        Text("YUV 4:4:4")
                            .tag(CodecOptionValue.kColorFormatYUV444)
                    } label: {
                        Text(markdown: String(localized: "session-settings.projection.codec.color_format", defaultValue: "색상 포맷"))
                        switch specification.options[.colorFormat] {
                        case .kColorFormatAuto:
                            Text(markdown: String(localized: "session-settings.projection.codec.color_format.auto_desc", defaultValue: "최적의 색상 포맷을 자동으로 선택합니다."))
                        case .kColorFormatYUV420:
                            Text(markdown: String(localized: "session-settings.projection.codec.color_format.yuv420_desc", defaultValue: "YUV 4:2:0 색상 포맷을 사용합니다. 대부분의 기기에서 호환됩니다."))
                        case .kColorFormatYUV444:
                            Text(markdown: String(localized: "session-settings.projection.codec.color_format.yuv444_desc", defaultValue: "YUV 4:4:4 색상 포맷을 사용합니다.\n텍스트 가독성이 향상되지만, 대역폭 사용량이 늘어나고 호환성이 떨어질 수 있습니다."))
                        default:
                            Text(markdown: String(localized: "session-settings.projection.codec.color_format.default_desc", defaultValue: "색상 포맷을 설정합니다."))
                        }
                    }

                    Picker(selection: $specification.options[.colorRange]) {
                        Text(markdown: String(localized: "session-settings.projection.codec.color_range.limited", defaultValue: "제한됨"))
                            .tag(CodecOptionValue.kColorRangeLimited)

                        Text(markdown: String(localized: "session-settings.projection.codec.color_range.full", defaultValue: "전체"))
                            .tag(CodecOptionValue.kColorRangeFull)
                    } label: {
                        Text(markdown: String(localized: "session-settings.projection.codec.color_range", defaultValue: "색상 범위"))
                        switch specification.options[.colorRange] {
                        case .kColorRangeLimited:
                            let range = specification.options[.dynamicRange] == .kDynamicRangeHDR ? "(64~940)" : "(16~235)"
                            Text(String(format: String(localized: "session-settings.projection.codec.color_range.limited_desc_format", defaultValue: "제한된 색상 범위 %@를 사용합니다."), range))
                        case .kColorRangeFull:
                            let range = specification.options[.dynamicRange] == .kDynamicRangeHDR ? "(0~1023)" : "(0~255)"
                            Text(String(format: String(localized: "session-settings.projection.codec.color_range.full_desc_format", defaultValue: "전체 색상 범위 %@를 사용합니다.\n색상 재현이 더 좋지만, 일부 기기에서 호환성 문제가 발생할 수 있습니다."), range))
                        default:
                            Text(markdown: String(localized: "session-settings.projection.codec.color_range.default_desc", defaultValue: "색상 범위를 설정합니다."))
                        }
                    }

                    Picker(selection: $specification.options[.profile]) {
                        Text(markdown: String(localized: "common.auto", defaultValue: "자동"))
                            .tag(CodecOptionValue.kProfileAuto)

                        if specification.fourCC == .avc1 {
                            h264ProfileOptions()
                        }

                        if specification.fourCC == .hvc1 {
                            hevcProfileOptions()
                        }
                    } label: {
                        Text(markdown: String(localized: "session-settings.projection.codec.profile", defaultValue: "코덱 프로파일"))
                        switch specification.options[.profile] {
                        case .kProfileAuto:
                            Text(markdown: String(localized: "session-settings.projection.codec.profile.auto_desc", defaultValue: "최적의 코덱 프로파일을 자동으로 선택합니다."))
                        case .kProfileH264Baseline:
                            Text(markdown: String(localized: "session-settings.projection.codec.profile.h264_baseline_desc", defaultValue: "호환성이 높은 Baseline Profile을 사용합니다.\n코덱의 고급 기능을 사용할 수 없기 때문에 압축률과 화질이 낮습니다."))
                        case .kProfileH264Main:
                            Text(markdown: String(localized: "session-settings.projection.codec.profile.h264_main_desc", defaultValue: "Main Profile을 사용합니다.\n대부분의 기기에서 적절한 호환성과 압축률을 제공합니다."))
                        case .kProfileH264High:
                            Text(markdown: String(localized: "session-settings.projection.codec.profile.h264_high_desc", defaultValue: "High Profile을 사용합니다.\n고급 기능을 사용하여 최고의 압축률과 화질을 제공합니다."))
                        case .kProfileHEVCMain:
                            Text(markdown: String(localized: "session-settings.projection.codec.profile.hevc_main_desc", defaultValue: "Main Profile을 사용합니다.\n대부분의 기기에서 적절한 호환성과 압축률을 제공합니다."))
                        case .kProfileHEVCMain10:
                            Text(markdown: String(localized: "session-settings.projection.codec.profile.hevc_main10_desc", defaultValue: "Main10 Profile을 사용합니다.\n10-bit 색상 지원으로 더 풍부한 색상을 제공합니다."))
                        default:
                            Text(markdown: String(localized: "session-settings.projection.codec.profile.default_desc", defaultValue: "코덱 프로파일을 설정합니다."))
                        }
                    }
                    .onChange(of: specification.options[.profile]) { _, newValue in
                        if !specification.isEligibleForHDR.isEligible,
                           specification.options[.dynamicRange] == .kDynamicRangeHDR {
                            specification.options[.dynamicRange] = .kDynamicRangeSDR
                        }
                    }

                    Picker(selection: $specification.options[.dynamicRange]) {
                        Text("SDR (Standard Dynamic Range)")
                            .tag(CodecOptionValue.kDynamicRangeSDR)

                        Text("HDR (High Dynamic Range)")
                            .tag(CodecOptionValue.kDynamicRangeHDR)
                    } label: {
                        Text(markdown: String(localized: "session-settings.projection.codec.dynamic_range", defaultValue: "다이나믹 레인지"))
                        switch specification.options[.dynamicRange] {
                        case .kDynamicRangeSDR:
                            Text(markdown: String(localized: "session-settings.projection.codec.dynamic_range.sdr_desc", defaultValue: "표준 다이나믹 레인지를 사용합니다."))
                        case .kDynamicRangeHDR:
                            Text(markdown: String(localized: "session-settings.projection.codec.dynamic_range.hdr_desc", defaultValue: "사용 가능한 경우 HDR 다이나믹 레인지를 사용합니다."))
                        default:
                            Text(markdown: String(localized: "session-settings.projection.codec.dynamic_range.default_desc", defaultValue: "다이나믹 레인지를 설정합니다."))
                        }
                    }.disabled(!specification.isEligibleForHDR.isEligible)

                } header: {
#if os(macOS)
                    Text(String(format: String(localized: "session-settings.projection.codec.title_format", defaultValue: "%@ 코덱 설정"), specification.displayTitle))
#endif
                }
            }
        }
    }

    // MARK: - Tab Content (shared)

    @ViewBuilder
    var tabContent: some View {
        TabView {
            basicSettingsView
                .tabItem {
                    Image(systemName: "videoprojector.fill")
                    Text(String(localized: "session-settings.projection.codec.tab.basic", defaultValue: "기본 설정"))
                }
            detailsTab
                .tabItem {
                    Image(systemName: "gearshape.2.fill")
                    Text(String(localized: "session-settings.projection.codec.tab.advanced", defaultValue: "고급 설정"))
                }
        }
    }

    // MARK: - Body (platform-specific)

#if os(macOS)
    var body: some View {
        VStack {
            tabContent

            HStack {
                Button(String(localized: "common.cancel", defaultValue: "취소")) {
                    dismiss()
                }
                Button(String(localized: "common.save", defaultValue: "저장")) {
                    onSave(specification)
                }
            }
            .padding(.bottom)
        }
    }
#elseif os(iOS)
    var body: some View {
        NavigationStack {
            tabContent
                .navigationTitle(String(format: String(localized: "session-settings.projection.codec.title_format", defaultValue: "%@ 코덱 설정"), specification.displayTitle))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(String(localized: "common.cancel", defaultValue: "취소")) {
                            dismiss()
                        }
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "common.save", defaultValue: "저장"), role: .compatibleConfirm) {
                            onSave(specification)
                        }
                    }
                }
        }
    }
#endif
}

// MARK: - Quality Policy Section

private extension CodecSpecificationSheet {
    @ViewBuilder
    func qualityPolicySection() -> some View {
        Section {
            Picker(selection: qualityModeBinding) {
                Text(markdown: String(localized: "session-settings.projection.codec.quality.auto", defaultValue: "자동 조정 (권장)"))
                    .tag("auto")
                Text(markdown: String(localized: "session-settings.projection.codec.quality.constantBitrate", defaultValue: "고정 비트레이트"))
                    .tag("constantBitrate")
                Text(markdown: String(localized: "session-settings.projection.codec.quality.variableBitrate", defaultValue: "가변 비트레이트"))
                    .tag("variableBitrate")
                Text(markdown: String(localized: "session-settings.projection.codec.quality.lossless", defaultValue: "무손실 (권장하지 않음)"))
                    .tag("lossless")
            } label: {
                Text(markdown: String(localized: "session-settings.projection.codec.quality.title", defaultValue: "품질 정책"))
                qualityPolicyDescription()
            }

            switch specification.quality {
            case .constantBitrate(let bitrateKbps):
                constantBitrateControls(bitrateKbps: bitrateKbps)
            case .variableBitrate(let targetBitrateKbps, let maxBitrateKbps):
                variableBitrateControls(targetBitrateKbps: targetBitrateKbps, maxBitrateKbps: maxBitrateKbps)
            case .lossless(let mode):
                losslessModeControls(mode: mode)
            default:
                EmptyView()
            }
        } footer: {
            if specification.quality.modeTag != "auto" {
                Text(String(localized: "session-settings.projection.codec.quality.manual_warning", defaultValue: "참고: 이 정책을 사용하면 네트워크 상태에 따른 퀄리티 디그레이드가 동작하지 않게 됩니다."))
            }
        }
    }

    @ViewBuilder
    func qualityPolicyDescription() -> some View {
        switch specification.quality.modeTag {
        case "auto":
            Text(markdown: String(
                localized: "session-settings.projection.codec.auto.description",
                defaultValue: "서버가 네트워크 환경과 클라이언트 측의 컴퓨팅 속도에 맞춰 자동으로 화면 품질을 결정합니다."
            ))
        case "constantBitrate":
            Text(markdown: String(
                localized: "session-settings.projection.codec.constantBitrate.description",
                defaultValue: "사용자가 지정한 비트레이트 값을 사용하도록 서버에게 요구합니다."
            ))
        case "variableBitrate":
            Text(markdown: String(
                localized: "session-settings.projection.codec.variableBitrate.description",
                defaultValue: "가변 비트레이트를 사용하도록 서버에게 요구합니다."
            ))
        case "lossless":
            Text(markdown: String(
                localized: "session-settings.projection.codec.lossless.description",
                defaultValue: "무손실 압축을 사용하도록 요구합니다.\n상당한 네트워크 대역폭을 사용하기 때문에 빠른 속도의 인터넷 연결을 필요로 합니다."
            ))
        default:
            Text(markdown: String(localized: "session-settings.projection.codec.quality.default_desc", defaultValue: "품질 정책을 설정합니다."))
        }
    }

    @ViewBuilder
    func constantBitrateControls(bitrateKbps: Int32) -> some View {
        SettingsEntry(
            title: String(localized: "session-settings.projection.codec.constantBitrateSlider.title", defaultValue: "비트레이트"),
            subtitle: String(
                localized: "session-settings.projection.codec.constantBitrateSlider.subtitle",
                defaultValue: "\(bitrateKbps / 1000)Mbps"
            )
        ) {
            Slider(
                value: constantBitrateBinding,
                in: 1000...20000,
                step: 1000,
                minimumValueLabel: Text("1Mbps"),
                maximumValueLabel: Text("20Mbps")
            ) {
            }
        }
    }

    @ViewBuilder
    func variableBitrateControls(targetBitrateKbps: Int32, maxBitrateKbps: Int32) -> some View {
        SettingsEntry(
            title: String(localized: "session-settings.projection.codec.variableBitrate.targetBitrateSlider.title", defaultValue: "타겟 비트레이트"),
            subtitle: String(
                localized: "session-settings.projection.codec.constantBitrateSlider.subtitle",
                defaultValue: "\(targetBitrateKbps / 1000)Mbps"
            )
        ) {
            Slider(
                value: variableBitrateTargetBinding(maxBitrateKbps: maxBitrateKbps),
                in: 1000...20000,
                step: 1000,
                minimumValueLabel: Text("1Mbps"),
                maximumValueLabel: Text("20Mbps")
            ) {
            }
        }

        SettingsEntry(
            title: String(localized: "session-settings.projection.codec.variableBitrate.maxBitrateSlider.title", defaultValue: "최대 비트레이트"),
            subtitle: String(
                localized: "session-settings.projection.codec.constantBitrateSlider.subtitle",
                defaultValue: "\(maxBitrateKbps / 1000)Mbps"
            )
        ) {
            Slider(
                value: variableBitrateMaxBinding(targetBitrateKbps: targetBitrateKbps),
                in: 1000...20000,
                step: 1000,
                minimumValueLabel: Text("1Mbps"),
                maximumValueLabel: Text("20Mbps")
            ) {
            }
        }
    }

    @ViewBuilder
    func losslessModeControls(mode: LosslessQualityMode) -> some View {
        Picker(selection: $specification.quality) {
            Text(String(localized: "session-settings.projection.codec.lossless.mode.balanced", defaultValue: "자동"))
                .tag(Codec.Quality.lossless(mode: .balancedPriority))

            Text(String(localized: "session-settings.projection.codec.lossless.mode.compression", defaultValue: "압축률 우선"))
                .tag(Codec.Quality.lossless(mode: .compressionPriority))

            Text(String(localized: "session-settings.projection.codec.lossless.mode.speed", defaultValue: "압축 속도 우선"))
                .tag(Codec.Quality.lossless(mode: .speedPriority))
        } label: {
            Text(String(localized: "session-settings.projection.codec.lossless.mode.title", defaultValue: "무손실 압축 모드"))

            switch mode {
            case .balancedPriority:
                Text(String(localized: "session-settings.projection.codec.lossless.mode.balanced_desc", defaultValue: "성능과 압축률 간의 균형을 맞춥니다."))
            case .compressionPriority:
                Text(String(localized: "session-settings.projection.codec.lossless.mode.compression_desc", defaultValue: "압축률을 우선시 합니다. 딜레이가 늘어날 수 있습니다."))
            case .speedPriority:
                Text(String(localized: "session-settings.projection.codec.lossless.mode.speed_desc", defaultValue: "압축 속도를 우선시 합니다. 대역폭 사용량이 늘어날 수 있습니다."))
            default:
                Text(String(localized: "session-settings.projection.codec.lossless.mode.default_desc", defaultValue: "무손실 압축 모드를 선택합니다."))
            }
        }
    }
}

// MARK: - Bindings

private extension CodecSpecificationSheet {
    var qualityModeBinding: Binding<String> {
        Binding<String>(
            get: { specification.quality.modeTag },
            set: { specification.quality = .defaultValue(for: $0) }
        )
    }

    var constantBitrateBinding: Binding<Double> {
        Binding<Double>(
            get: {
                if case .constantBitrate(let bitrateKbps) = specification.quality {
                    return Double(bitrateKbps)
                }
                return 3000
            },
            set: { specification.quality = .constantBitrate(bitrateKbps: Int32($0)) }
        )
    }

    func variableBitrateTargetBinding(maxBitrateKbps: Int32) -> Binding<Double> {
        Binding<Double>(
            get: {
                if case .variableBitrate(let target, _) = specification.quality {
                    return Double(target)
                }
                return 3000
            },
            set: { specification.quality = .variableBitrate(targetBitrateKbps: Int32($0), maxBitrateKbps: maxBitrateKbps) }
        )
    }

    func variableBitrateMaxBinding(targetBitrateKbps: Int32) -> Binding<Double> {
        Binding<Double>(
            get: {
                if case .variableBitrate(_, let max) = specification.quality {
                    return Double(max)
                }
                return 6000
            },
            set: { specification.quality = .variableBitrate(targetBitrateKbps: targetBitrateKbps, maxBitrateKbps: Int32($0)) }
        )
    }
}

// MARK: - Codec Profile Options

fileprivate extension CodecSpecificationSheet {
    @ViewBuilder
    func h264ProfileOptions() -> some View {
        Text(markdown: String(localized: "session-settings.projection.codec.profile.h264_baseline", defaultValue: "Baseline Profile (가장 높은 호환성, 압축률 낮음)"))
            .tag(CodecOptionValue.kProfileH264Baseline)
        Text("Main Profile")
            .tag(CodecOptionValue.kProfileH264Main)
        Text(markdown: String(localized: "session-settings.projection.codec.profile.h264_high", defaultValue: "High Profile (가장 낮은 호환성, 압축률 높음)"))
            .tag(CodecOptionValue.kProfileH264High)
    }

    @ViewBuilder
    func hevcProfileOptions() -> some View {
        Text("Main Profile")
            .tag(CodecOptionValue.kProfileHEVCMain)
        Text(markdown: String(localized: "session-settings.projection.codec.profile.hevc_main10", defaultValue: "Main10 Profile (10-bit 색상 지원)"))
            .tag(CodecOptionValue.kProfileHEVCMain10)
    }
}

// MARK: - Codec.Quality Helpers

fileprivate extension Codec.Quality {
    var modeTag: String {
        switch self {
        case .auto: return "auto"
        case .constantBitrate: return "constantBitrate"
        case .fixedQuality: return "fixedQuality"
        case .lossless: return "lossless"
        case .variableBitrate: return "variableBitrate"
        }
    }

    static func defaultValue(for tag: String) -> Codec.Quality {
        switch tag {
        case "auto": return .auto(mode: .balancedPriority)
        case "constantBitrate": return .constantBitrate(bitrateKbps: 3000)
        case "lossless": return .lossless(mode: .balancedPriority)
        case "variableBitrate": return .variableBitrate(targetBitrateKbps: 3000, maxBitrateKbps: 6000)
        default: return .auto(mode: .balancedPriority)
        }
    }
}

#Preview {
    CodecSpecificationSheet(specification: .hevc) { spec in
        print("Saved specification: \(spec)")
    }
}
