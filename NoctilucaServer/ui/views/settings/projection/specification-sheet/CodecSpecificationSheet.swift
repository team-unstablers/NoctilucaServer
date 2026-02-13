//
//  CodecSpecificationSheet.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation

import SwiftUI

import SiriusKit

enum CodecSpecificationSheetAction {
    case save(CodecSpecification)
    case cancel
}

fileprivate enum QualityModeTag: Hashable {
    case auto
    case constantBitrate
    case variableBitrate
    case fixedQuality
    case lossless
}

struct CodecSpecificationSheet: View {
    let actionHandler: (CodecSpecificationSheetAction) -> Void
    
    @State
    var specification: CodecSpecification = .h264
    
    init(specification: CodecSpecification, actionHandler: @escaping (CodecSpecificationSheetAction) -> Void) {
        self.specification = specification
        self.actionHandler = actionHandler
    }
    
    var body: some View {
        VStack {
            Form {
                Section {
                    Picker(selection: $specification.options[.hardwareAcceleration]) {
                        Text(markdown: String(localized: "settings.projection.codec_sheet.hardware_acceleration.auto", defaultValue: "자동"))
                            .tag(CodecOptionValue.kHardwareAccelerationAuto)
                        Text(markdown: String(localized: "settings.projection.codec_sheet.hardware_acceleration.disabled", defaultValue: "사용 안 함"))
                            .tag(CodecOptionValue.kHardwareAccelerationFalse)
                    } label: {
                        Text(markdown: String(localized: "settings.projection.codec_sheet.hardware_acceleration.title", defaultValue: "하드웨어 가속"))
                        switch specification.options[.hardwareAcceleration] {
                        case .kHardwareAccelerationAuto:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.hardware_acceleration.auto_description", defaultValue: "가능한 경우 하드웨어 가속을 사용합니다."))
                        case .kHardwareAccelerationFalse:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.hardware_acceleration.disabled_description", defaultValue: "하드웨어 가속을 사용하지 않고, 소프트웨어 압축만 사용합니다.\n컴퓨팅 자원이 부족해질 수 있습니다."))
                        default:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.hardware_acceleration.description", defaultValue: "하드웨어 가속 사용 여부를 설정합니다."))
                        }
                    }
                    
                    Picker(selection: $specification.options[.colorFormat]) {
                        Text(markdown: String(localized: "settings.projection.codec_sheet.color_format.auto", defaultValue: "자동"))
                            .tag(CodecOptionValue.kColorFormatAuto)
                        Text(markdown: String(localized: "settings.projection.codec_sheet.color_format.yuv420", defaultValue: "YUV 4:2:0"))
                            .tag(CodecOptionValue.kColorFormatYUV420)
                        Text(markdown: String(localized: "settings.projection.codec_sheet.color_format.yuv444", defaultValue: "YUV 4:4:4"))
                            .tag(CodecOptionValue.kColorFormatYUV444)
                    } label: {
                        Text(markdown: String(localized: "settings.projection.codec_sheet.color_format.title", defaultValue: "색상 포맷"))
                        switch specification.options[.colorFormat] {
                        case .kColorFormatAuto:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.color_format.auto_description", defaultValue: "최적의 색상 포맷을 자동으로 선택합니다."))
                        case .kColorFormatYUV420:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.color_format.yuv420_description", defaultValue: "YUV 4:2:0 색상 포맷을 사용합니다. 대부분의 기기에서 호환됩니다."))
                        case .kColorFormatYUV444:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.color_format.yuv444_description", defaultValue: "YUV 4:4:4 색상 포맷을 사용합니다.\n텍스트 가독성이 향상되지만, 대역폭 사용량이 늘어나고 호환성이 떨어질 수 있습니다."))
                        default:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.color_format.description", defaultValue: "색상 포맷을 설정합니다."))
                        }
                    }
                    
                    Picker(selection: $specification.options[.colorRange]) {
                        Text(markdown: String(localized: "settings.projection.codec_sheet.color_range.limited", defaultValue: "제한됨"))
                            .tag(CodecOptionValue.kColorRangeLimited)

                        Text(markdown: String(localized: "settings.projection.codec_sheet.color_range.full", defaultValue: "전체"))
                            .tag(CodecOptionValue.kColorRangeFull)
                    } label: {
                        Text(markdown: String(localized: "settings.projection.codec_sheet.color_range.title", defaultValue: "색상 범위"))
                        switch specification.options[.colorRange] {
                        case .kColorRangeLimited:
                            let range = specification.options[.dynamicRange] == .kDynamicRangeHDR ? "(64~940)" : "(16~235)"
                            Text(markdown: String(localized: "settings.projection.codec_sheet.color_range.limited_description", defaultValue: "제한된 색상 범위 \(range)를 사용합니다."))
                        case .kColorRangeFull:
                            let range = specification.options[.dynamicRange] == .kDynamicRangeHDR ? "(0~1023)" : "(0~255)"
                            Text(markdown: String(localized: "settings.projection.codec_sheet.color_range.full_description", defaultValue: "전체 색상 범위 \(range)를 사용합니다.\n색상 재현이 더 좋지만, 일부 기기에서 호환성 문제가 발생할 수 있습니다."))
                        default:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.color_range.description", defaultValue: "색상 범위를 설정합니다."))
                        }
                    }
                    
                    Picker(selection: $specification.options[.profile]) {
                        Text(markdown: String(localized: "settings.projection.codec_sheet.profile.auto", defaultValue: "자동"))
                            .tag(CodecOptionValue.kProfileAuto)

                        if specification.fourCC == .avc1 {
                            h264ProfileOptions()
                        }

                        if specification.fourCC == .hvc1 {
                            hevcProfileOptions()
                        }
                    } label: {
                        Text(markdown: String(localized: "settings.projection.codec_sheet.profile.title", defaultValue: "코덱 프로파일"))
                        switch specification.options[.profile] {
                        case .kProfileAuto:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.profile.auto_description", defaultValue: "최적의 코덱 프로파일을 자동으로 선택합니다."))
                        case .kProfileH264Baseline:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.profile.h264_baseline_description", defaultValue: "호환성이 높은 Baseline Profile을 사용합니다.\n코덱의 고급 기능을 사용할 수 없기 때문에 압축률과 화질이 낮습니다."))
                        case .kProfileH264Main:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.profile.h264_main_description", defaultValue: "Main Profile을 사용합니다.\n대부분의 기기에서 적절한 호환성과 압축률을 제공합니다."))
                        case .kProfileH264High:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.profile.h264_high_description", defaultValue: "High Profile을 사용합니다.\n고급 기능을 사용하여 최고의 압축률과 화질을 제공합니다."))
                        case .kProfileHEVCMain:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.profile.hevc_main_description", defaultValue: "Main Profile을 사용합니다.\n대부분의 기기에서 적절한 호환성과 압축률을 제공합니다."))
                        case .kProfileHEVCMain10:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.profile.hevc_main10_description", defaultValue: "Main10 Profile을 사용합니다.\n10-bit 색상 지원으로 더 풍부한 색상을 제공합니다."))
                        default:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.profile.description", defaultValue: "코덱 프로파일을 설정합니다."))
                        }
                    }
                    .onChange(of: specification.options[.profile]) { _, newValue in
                        if !specification.isEligibleForHDR.isEligible,
                           specification.options[.dynamicRange] == .kDynamicRangeHDR {
                            // sanitize
                            specification.options[.dynamicRange] = .kDynamicRangeSDR
                        }
                    }
                    
                    Picker(selection: $specification.options[.dynamicRange]) {
                        Text(markdown: String(localized: "settings.projection.codec_sheet.dynamic_range.sdr", defaultValue: "SDR (Standard Dynamic Range)"))
                            .tag(CodecOptionValue.kDynamicRangeSDR)

                        Text(markdown: String(localized: "settings.projection.codec_sheet.dynamic_range.hdr", defaultValue: "HDR (High Dynamic Range)"))
                            .tag(CodecOptionValue.kDynamicRangeHDR)
                    } label: {
                        Text(markdown: String(localized: "settings.projection.codec_sheet.dynamic_range.title", defaultValue: "다이나믹 레인지"))
                        switch specification.options[.dynamicRange] {
                        case .kDynamicRangeSDR:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.dynamic_range.sdr_description", defaultValue: "표준 다이나믹 레인지를 사용합니다."))
                        case .kDynamicRangeHDR:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.dynamic_range.hdr_description", defaultValue: "사용 가능한 경우 HDR 다이나믹 레인지를 사용합니다."))
                        default:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.dynamic_range.description", defaultValue: "다이나믹 레인지를 설정합니다."))
                        }
                    }.disabled(!specification.isEligibleForHDR.isEligible)
                    
                    Slider(
                        value: .convert($specification.maximumResolutionLevel.rawValue),
                        in: 0...Double(CodecResolutionLevel.hd4k.rawValue),
                        step: 1,
                        minimumValueLabel: Text(markdown: String(localized: "settings.projection.codec_sheet.resolution.auto", defaultValue: "자동")),
                        maximumValueLabel: Text(markdown: String(localized: "settings.projection.codec_sheet.resolution.4k", defaultValue: "4K"))
                    ) {
                        Text(markdown: String(localized: "settings.projection.codec_sheet.resolution.title", defaultValue: "최대 해상도"))
                        if specification.maximumResolutionLevel == .unlimited {
                            Text(markdown: String(localized: "settings.projection.codec_sheet.resolution.auto_description", defaultValue: "클라이언트의 협상 내용을 기반으로 최대 해상도를 결정합니다."))
                        } else {
                            Text(markdown: String(localized: "settings.projection.codec_sheet.resolution.level_description", defaultValue: "최대 해상도를 \(specification.maximumResolutionLevel.displayText)으로 설정합니다."))
                        }
                    }
                    
                    Slider(
                        value: $specification.frameRate,
                        in: 0...60,
                        step: 15,
                        minimumValueLabel: Text(markdown: String(localized: "settings.projection.codec_sheet.framerate.auto", defaultValue: "자동")),
                        maximumValueLabel: Text(markdown: String(localized: "settings.projection.codec_sheet.framerate.60fps", defaultValue: "60 FPS"))
                    ) {
                        Text(markdown: String(localized: "settings.projection.codec_sheet.framerate.title", defaultValue: "프레임 속도"))
                        if specification.frameRate == 0 {
                            Text(markdown: String(localized: "settings.projection.codec_sheet.framerate.auto_description", defaultValue: "클라이언트의 협상 내용을 기반으로 프레임 속도를 결정합니다."))
                        } else {
                            Text(markdown: String(localized: "settings.projection.codec_sheet.framerate.value_description", defaultValue: "프레임 속도를 최대 \(Int(specification.frameRate)) FPS로 설정합니다."))
                        }
                    }
                    
                    Picker(selection: $specification.options[.displayDensity]) {
                        Text(markdown: String(localized: "settings.projection.codec_sheet.display_density.auto", defaultValue: "자동"))
                            .tag(CodecOptionValue.kDisplayDensityAuto)

                        Text(markdown: String(localized: "settings.projection.codec_sheet.display_density.performance", defaultValue: "성능 우선"))
                            .tag(CodecOptionValue.kDisplayDensityPerformance)

                        Text(markdown: String(localized: "settings.projection.codec_sheet.display_density.best", defaultValue: "화질 우선"))
                            .tag(CodecOptionValue.kDisplayDensityBest)
                    } label: {
                        Text(markdown: String(localized: "settings.projection.codec_sheet.display_density.title", defaultValue: "디스플레이 밀도"))
                        switch specification.options[.displayDensity] {
                        case .kDisplayDensityAuto:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.display_density.auto_description", defaultValue: "디스플레이 밀도를 자동으로 선택합니다."))
                        case .kDisplayDensityPerformance:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.display_density.performance_description", defaultValue: "성능을 우선시하여 디스플레이 밀도를 설정합니다.\n대부분의 경우 1x 밀도로 설정됩니다."))
                        case .kDisplayDensityBest:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.display_density.best_description", defaultValue: "HIDPI / Retina 디스플레이 밀도를 사용하려 노력합니다.\n더 나은 화질을 제공하지만, 높은 대역폭과 컴퓨팅 자원을 사용합니다."))

                        default:
                            Text(markdown: String(localized: "settings.projection.codec_sheet.display_density.description", defaultValue: "디스플레이 밀도를 설정합니다."))
                        }
                    }
                } header: {
                    Text(markdown: String(localized: "settings.projection.codec_sheet.header", defaultValue: "\(specification.displayTitle) 코덱 설정"))
                }

                Section {
                    qualityPicker()
                    qualityParameters()
                } header: {
                    Text(markdown: String(localized: "settings.projection.codec_sheet.quality_header", defaultValue: "품질 설정"))
                }
            }
            .formStyle(.grouped)
            
            HStack {
                Button(String(localized: "settings.projection.codec_sheet.cancel", defaultValue: "취소")) {
                    actionHandler(.cancel)
                }
                Button(String(localized: "settings.projection.codec_sheet.save", defaultValue: "저장")) {
                    actionHandler(.save(specification))
                }
            }
            .padding(.bottom)
        }
    }
}

fileprivate extension CodecSpecificationSheet {
    var isImageCodec: Bool {
        specification.fourCC == .zrle || specification.fourCC == .mjpg || specification.fourCC == .webp
    }

    var qualityModeBinding: Binding<QualityModeTag> {
        Binding(
            get: {
                switch specification.quality {
                case .auto: return .auto
                case .constantBitrate: return .constantBitrate
                case .variableBitrate: return .variableBitrate
                case .fixedQuality: return .fixedQuality
                case .lossless: return .lossless
                }
            },
            set: { newTag in
                switch newTag {
                case .auto:
                    specification.quality = .auto(mode: 0)
                case .constantBitrate:
                    specification.quality = .constantBitrate(bitrateKbps: 5000)
                case .variableBitrate:
                    specification.quality = .variableBitrate(targetBitrateKbps: 5000, maxBitrateKbps: 10000)
                case .fixedQuality:
                    specification.quality = .fixedQuality(factor: 50)
                case .lossless:
                    specification.quality = .lossless(mode: 0)
                }
            }
        )
    }

    var autoQualityModeBinding: Binding<AutoQualityMode> {
        Binding(
            get: {
                if case .auto(let mode) = specification.quality {
                    return AutoQualityMode(rawValue: mode)
                }
                return .balancedPriority
            },
            set: { newMode in
                specification.quality = .auto(mode: newMode.rawValue)
            }
        )
    }

    var constantBitrateBinding: Binding<Int32> {
        Binding(
            get: {
                if case .constantBitrate(let bitrateKbps) = specification.quality {
                    return bitrateKbps
                }
                return 5000
            },
            set: { newValue in
                specification.quality = .constantBitrate(bitrateKbps: newValue)
            }
        )
    }

    var variableBitrateTargetBinding: Binding<Int32> {
        Binding(
            get: {
                if case .variableBitrate(let targetBitrateKbps, _) = specification.quality {
                    return targetBitrateKbps
                }
                return 5000
            },
            set: { newValue in
                if case .variableBitrate(_, let maxBitrateKbps) = specification.quality {
                    specification.quality = .variableBitrate(targetBitrateKbps: newValue, maxBitrateKbps: maxBitrateKbps)
                }
            }
        )
    }

    var variableBitrateMaxBinding: Binding<Int32> {
        Binding(
            get: {
                if case .variableBitrate(_, let maxBitrateKbps) = specification.quality {
                    return maxBitrateKbps
                }
                return 10000
            },
            set: { newValue in
                if case .variableBitrate(let targetBitrateKbps, _) = specification.quality {
                    specification.quality = .variableBitrate(targetBitrateKbps: targetBitrateKbps, maxBitrateKbps: newValue)
                }
            }
        )
    }

    var fixedQualityFactorBinding: Binding<Double> {
        Binding(
            get: {
                if case .fixedQuality(let factor) = specification.quality {
                    return Double(factor)
                }
                return 50.0
            },
            set: { newValue in
                specification.quality = .fixedQuality(factor: Int32(newValue))
            }
        )
    }

    var losslessQualityModeBinding: Binding<LosslessQualityMode> {
        Binding(
            get: {
                if case .lossless(let mode) = specification.quality {
                    return LosslessQualityMode(rawValue: mode)
                }
                return .balancedPriority
            },
            set: { newMode in
                specification.quality = .lossless(mode: newMode.rawValue)
            }
        )
    }

    @ViewBuilder
    func qualityPicker() -> some View {
        Picker(selection: qualityModeBinding) {
            Text(markdown: String(localized: "settings.projection.codec_sheet.quality_mode.auto", defaultValue: "자동"))
                .tag(QualityModeTag.auto)

            if !isImageCodec {
                Text(markdown: String(localized: "settings.projection.codec_sheet.quality_mode.cbr", defaultValue: "고정 비트레이트 (CBR)"))
                    .tag(QualityModeTag.constantBitrate)

                Text(markdown: String(localized: "settings.projection.codec_sheet.quality_mode.vbr", defaultValue: "가변 비트레이트 (VBR)"))
                    .tag(QualityModeTag.variableBitrate)

                Text(markdown: String(localized: "settings.projection.codec_sheet.quality_mode.fixed_quality", defaultValue: "고정 품질 (CQP/CRF)"))
                    .tag(QualityModeTag.fixedQuality)

                Text(markdown: String(localized: "settings.projection.codec_sheet.quality_mode.lossless", defaultValue: "무손실"))
                    .tag(QualityModeTag.lossless)
            }
        } label: {
            Text(markdown: String(localized: "settings.projection.codec_sheet.quality_mode.title", defaultValue: "품질 모드"))
            qualityModeDescription()
        }
    }

    @ViewBuilder
    func qualityModeDescription() -> some View {
        switch specification.quality {
        case .auto:
            Text(markdown: String(localized: "settings.projection.codec_sheet.quality_mode.auto_description", defaultValue: "네트워크 상태에 따라 자동으로 품질을 조절합니다."))
        case .constantBitrate:
            Text(markdown: String(localized: "settings.projection.codec_sheet.quality_mode.cbr_description", defaultValue: "고정 비트레이트로 안정적인 대역폭을 사용합니다."))
        case .variableBitrate:
            Text(markdown: String(localized: "settings.projection.codec_sheet.quality_mode.vbr_description", defaultValue: "가변 비트레이트로 품질과 대역폭의 균형을 맞춥니다."))
        case .fixedQuality:
            Text(markdown: String(localized: "settings.projection.codec_sheet.quality_mode.fixed_quality_description", defaultValue: "고정 품질 계수를 사용하여 일정한 화질을 유지합니다."))
        case .lossless:
            Text(markdown: String(localized: "settings.projection.codec_sheet.quality_mode.lossless_description", defaultValue: "무손실 압축을 사용하여 품질 저하 없이 전송합니다."))
        }
    }

    @ViewBuilder
    func qualityParameters() -> some View {
        switch specification.quality {
        case .auto(let mode):
            autoQualityParameters(mode: mode)
        case .constantBitrate(let bitrateKbps):
            constantBitrateParameters(bitrateKbps: bitrateKbps)
        case .variableBitrate(let targetBitrateKbps, let maxBitrateKbps):
            variableBitrateParameters(targetBitrateKbps: targetBitrateKbps, maxBitrateKbps: maxBitrateKbps)
        case .fixedQuality(let factor):
            fixedQualityParameters(factor: factor)
        case .lossless(let mode):
            losslessQualityParameters(mode: mode)
        }
    }

    @ViewBuilder
    func autoQualityParameters(mode: UInt32) -> some View {
        Picker(selection: autoQualityModeBinding) {
            Text(markdown: String(localized: "settings.projection.codec_sheet.auto_quality_strategy.balanced", defaultValue: "균형"))
                .tag(AutoQualityMode.balancedPriority)
            Text(markdown: String(localized: "settings.projection.codec_sheet.auto_quality_strategy.quality", defaultValue: "품질 우선"))
                .tag(AutoQualityMode.qualityPriority)
            Text(markdown: String(localized: "settings.projection.codec_sheet.auto_quality_strategy.performance", defaultValue: "성능 우선"))
                .tag(AutoQualityMode.performancePriority)
        } label: {
            Text(markdown: String(localized: "settings.projection.codec_sheet.auto_quality_strategy.title", defaultValue: "자동 품질 전략"))
            switch AutoQualityMode(rawValue: mode) {
            case .balancedPriority:
                Text(markdown: String(localized: "settings.projection.codec_sheet.auto_quality_strategy.balanced_description", defaultValue: "품질과 성능 간의 균형을 맞춥니다."))
            case .qualityPriority:
                Text(markdown: String(localized: "settings.projection.codec_sheet.auto_quality_strategy.quality_description", defaultValue: "가능한 최고의 품질을 우선시합니다."))
            case .performancePriority:
                Text(markdown: String(localized: "settings.projection.codec_sheet.auto_quality_strategy.performance_description", defaultValue: "가능한 최고의 성능을 우선시합니다."))
            default:
                Text(markdown: String(localized: "settings.projection.codec_sheet.auto_quality_strategy.description", defaultValue: "자동 품질 전략을 설정합니다."))
            }
        }
    }

    @ViewBuilder
    func constantBitrateParameters(bitrateKbps: Int32) -> some View {
        SettingsEntry(
            title: String(localized: "settings.projection.codec_sheet.bitrate.title", defaultValue: "비트레이트 (kbps)"),
            subtitle: String(localized: "settings.projection.codec_sheet.bitrate.description", defaultValue: "목표 비트레이트: \(bitrateKbps) kbps")
        ) {
            TextField(String(localized: "settings.projection.codec_sheet.bitrate.placeholder", defaultValue: "비트레이트"), value: constantBitrateBinding, format: .number)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
        }
    }

    @ViewBuilder
    func variableBitrateParameters(targetBitrateKbps: Int32, maxBitrateKbps: Int32) -> some View {
        SettingsEntry(
            title: String(localized: "settings.projection.codec_sheet.target_bitrate.title", defaultValue: "목표 비트레이트 (kbps)"),
            subtitle: String(localized: "settings.projection.codec_sheet.target_bitrate.description", defaultValue: "목표: \(targetBitrateKbps) kbps")
        ) {
            TextField(String(localized: "settings.projection.codec_sheet.target_bitrate.placeholder", defaultValue: "목표 비트레이트"), value: variableBitrateTargetBinding, format: .number)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
        }

        SettingsEntry(
            title: String(localized: "settings.projection.codec_sheet.max_bitrate.title", defaultValue: "최대 비트레이트 (kbps)"),
            subtitle: String(localized: "settings.projection.codec_sheet.max_bitrate.description", defaultValue: "최대: \(maxBitrateKbps) kbps")
        ) {
            TextField(String(localized: "settings.projection.codec_sheet.max_bitrate.placeholder", defaultValue: "최대 비트레이트"), value: variableBitrateMaxBinding, format: .number)
                .multilineTextAlignment(.trailing)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
        }
    }

    @ViewBuilder
    func fixedQualityParameters(factor: Int32) -> some View {
        Slider(
            value: fixedQualityFactorBinding,
            in: 0...100,
            step: 1,
            minimumValueLabel: Text(markdown: String(localized: "settings.projection.codec_sheet.quality_factor.min", defaultValue: "0")),
            maximumValueLabel: Text(markdown: String(localized: "settings.projection.codec_sheet.quality_factor.max", defaultValue: "100"))
        ) {
            Text(markdown: String(localized: "settings.projection.codec_sheet.quality_factor.title", defaultValue: "품질 계수"))
            Text(markdown: String(localized: "settings.projection.codec_sheet.quality_factor.description", defaultValue: "현재 품질 계수: \(factor)"))
        }
    }

    @ViewBuilder
    func losslessQualityParameters(mode: UInt32) -> some View {
        Picker(selection: losslessQualityModeBinding) {
            Text(markdown: String(localized: "settings.projection.codec_sheet.lossless_mode.balanced", defaultValue: "균형"))
                .tag(LosslessQualityMode.balancedPriority)
            Text(markdown: String(localized: "settings.projection.codec_sheet.lossless_mode.speed", defaultValue: "속도 우선"))
                .tag(LosslessQualityMode.speedPriority)
            Text(markdown: String(localized: "settings.projection.codec_sheet.lossless_mode.compression", defaultValue: "압축 우선"))
                .tag(LosslessQualityMode.compressionPriority)
        } label: {
            Text(markdown: String(localized: "settings.projection.codec_sheet.lossless_mode.title", defaultValue: "무손실 품질 모드"))
            switch LosslessQualityMode(rawValue: mode) {
            case .balancedPriority:
                Text(markdown: String(localized: "settings.projection.codec_sheet.lossless_mode.balanced_description", defaultValue: "성능과 압축률 간의 균형을 맞춥니다."))
            case .speedPriority:
                Text(markdown: String(localized: "settings.projection.codec_sheet.lossless_mode.speed_description", defaultValue: "성능을 우선시합니다. (압축률이 낮아질 수 있음)"))
            case .compressionPriority:
                Text(markdown: String(localized: "settings.projection.codec_sheet.lossless_mode.compression_description", defaultValue: "압축률을 우선시합니다. (성능이 낮아질 수 있음)"))
            default:
                Text(markdown: String(localized: "settings.projection.codec_sheet.lossless_mode.description", defaultValue: "무손실 품질 모드를 설정합니다."))
            }
        }
    }

    @ViewBuilder
    func h264ProfileOptions() -> some View {
        Text(markdown: String(localized: "settings.projection.codec_sheet.profile.h264_baseline", defaultValue: "Baseline Profile (가장 높은 호환성, 압축률 낮음)"))
            .tag(CodecOptionValue.kProfileH264Baseline)
        Text(markdown: String(localized: "settings.projection.codec_sheet.profile.h264_main", defaultValue: "Main Profile"))
            .tag(CodecOptionValue.kProfileH264Main)
        Text(markdown: String(localized: "settings.projection.codec_sheet.profile.h264_high", defaultValue: "High Profile (가장 낮은 호환성, 압축률 높음)"))
            .tag(CodecOptionValue.kProfileH264High)
    }

    @ViewBuilder
    func hevcProfileOptions() -> some View {
        Text(markdown: String(localized: "settings.projection.codec_sheet.profile.hevc_main", defaultValue: "Main Profile"))
            .tag(CodecOptionValue.kProfileHEVCMain)
        Text(markdown: String(localized: "settings.projection.codec_sheet.profile.hevc_main10", defaultValue: "Main10 Profile (10-bit 색상 지원)"))
            .tag(CodecOptionValue.kProfileHEVCMain10)
    }
}

#Preview {
    CodecSpecificationSheet(specification: .hevc) { action in
        switch action {
        case .save(let spec):
            print("Saved specification: \(spec)")
        case .cancel:
            print("Cancelled")
        }
    }
}
