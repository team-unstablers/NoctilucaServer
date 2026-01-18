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
                        Text(String(localized: "settings.projection.codec_sheet.hardware_acceleration.auto", defaultValue: "자동"))
                            .tag(CodecOptionValue.kHardwareAccelerationAuto)
                        Text(String(localized: "settings.projection.codec_sheet.hardware_acceleration.disabled", defaultValue: "사용 안 함"))
                            .tag(CodecOptionValue.kHardwareAccelerationFalse)
                    } label: {
                        Text(String(localized: "settings.projection.codec_sheet.hardware_acceleration.title", defaultValue: "하드웨어 가속"))
                        switch specification.options[.hardwareAcceleration] {
                        case .kHardwareAccelerationAuto:
                            Text(String(localized: "settings.projection.codec_sheet.hardware_acceleration.auto_description", defaultValue: "가능한 경우 하드웨어 가속을 사용합니다."))
                        case .kHardwareAccelerationFalse:
                            Text(String(localized: "settings.projection.codec_sheet.hardware_acceleration.disabled_description", defaultValue: "하드웨어 가속을 사용하지 않고, 소프트웨어 압축만 사용합니다.\n컴퓨팅 자원이 부족해질 수 있습니다."))
                        default:
                            Text(String(localized: "settings.projection.codec_sheet.hardware_acceleration.description", defaultValue: "하드웨어 가속 사용 여부를 설정합니다."))
                        }
                    }
                    
                    Picker(selection: $specification.options[.colorFormat]) {
                        Text(String(localized: "settings.projection.codec_sheet.color_format.auto", defaultValue: "자동"))
                            .tag(CodecOptionValue.kColorFormatAuto)
                        Text(String(localized: "settings.projection.codec_sheet.color_format.yuv420", defaultValue: "YUV 4:2:0"))
                            .tag(CodecOptionValue.kColorFormatYUV420)
                        Text(String(localized: "settings.projection.codec_sheet.color_format.yuv444", defaultValue: "YUV 4:4:4"))
                            .tag(CodecOptionValue.kColorFormatYUV444)
                    } label: {
                        Text(String(localized: "settings.projection.codec_sheet.color_format.title", defaultValue: "색상 포맷"))
                        switch specification.options[.colorFormat] {
                        case .kColorFormatAuto:
                            Text(String(localized: "settings.projection.codec_sheet.color_format.auto_description", defaultValue: "최적의 색상 포맷을 자동으로 선택합니다."))
                        case .kColorFormatYUV420:
                            Text(String(localized: "settings.projection.codec_sheet.color_format.yuv420_description", defaultValue: "YUV 4:2:0 색상 포맷을 사용합니다. 대부분의 기기에서 호환됩니다."))
                        case .kColorFormatYUV444:
                            Text(String(localized: "settings.projection.codec_sheet.color_format.yuv444_description", defaultValue: "YUV 4:4:4 색상 포맷을 사용합니다.\n텍스트 가독성이 향상되지만, 대역폭 사용량이 늘어나고 호환성이 떨어질 수 있습니다."))
                        default:
                            Text(String(localized: "settings.projection.codec_sheet.color_format.description", defaultValue: "색상 포맷을 설정합니다."))
                        }
                    }
                    
                    Picker(selection: $specification.options[.colorRange]) {
                        Text(String(localized: "settings.projection.codec_sheet.color_range.limited", defaultValue: "제한됨"))
                            .tag(CodecOptionValue.kColorRangeLimited)

                        Text(String(localized: "settings.projection.codec_sheet.color_range.full", defaultValue: "전체"))
                            .tag(CodecOptionValue.kColorRangeFull)
                    } label: {
                        Text(String(localized: "settings.projection.codec_sheet.color_range.title", defaultValue: "색상 범위"))
                        switch specification.options[.colorRange] {
                        case .kColorRangeLimited:
                            let range = specification.options[.dynamicRange] == .kDynamicRangeHDR ? "(64~940)" : "(16~235)"
                            Text(String(localized: "settings.projection.codec_sheet.color_range.limited_description", defaultValue: "제한된 색상 범위 \(range)를 사용합니다."))
                        case .kColorRangeFull:
                            let range = specification.options[.dynamicRange] == .kDynamicRangeHDR ? "(0~1023)" : "(0~255)"
                            Text(String(localized: "settings.projection.codec_sheet.color_range.full_description", defaultValue: "전체 색상 범위 \(range)를 사용합니다.\n색상 재현이 더 좋지만, 일부 기기에서 호환성 문제가 발생할 수 있습니다."))
                        default:
                            Text(String(localized: "settings.projection.codec_sheet.color_range.description", defaultValue: "색상 범위를 설정합니다."))
                        }
                    }
                    
                    Picker(selection: $specification.options[.profile]) {
                        Text(String(localized: "settings.projection.codec_sheet.profile.auto", defaultValue: "자동"))
                            .tag(CodecOptionValue.kProfileAuto)

                        if specification.fourCC == .avc1 {
                            h264ProfileOptions()
                        }

                        if specification.fourCC == .hvc1 {
                            hevcProfileOptions()
                        }
                    } label: {
                        Text(String(localized: "settings.projection.codec_sheet.profile.title", defaultValue: "코덱 프로파일"))
                        switch specification.options[.profile] {
                        case .kProfileAuto:
                            Text(String(localized: "settings.projection.codec_sheet.profile.auto_description", defaultValue: "최적의 코덱 프로파일을 자동으로 선택합니다."))
                        case .kProfileH264Baseline:
                            Text(String(localized: "settings.projection.codec_sheet.profile.h264_baseline_description", defaultValue: "호환성이 높은 Baseline Profile을 사용합니다.\n코덱의 고급 기능을 사용할 수 없기 때문에 압축률과 화질이 낮습니다."))
                        case .kProfileH264Main:
                            Text(String(localized: "settings.projection.codec_sheet.profile.h264_main_description", defaultValue: "Main Profile을 사용합니다.\n대부분의 기기에서 적절한 호환성과 압축률을 제공합니다."))
                        case .kProfileH264High:
                            Text(String(localized: "settings.projection.codec_sheet.profile.h264_high_description", defaultValue: "High Profile을 사용합니다.\n고급 기능을 사용하여 최고의 압축률과 화질을 제공합니다."))
                        case .kProfileHEVCMain:
                            Text(String(localized: "settings.projection.codec_sheet.profile.hevc_main_description", defaultValue: "Main Profile을 사용합니다.\n대부분의 기기에서 적절한 호환성과 압축률을 제공합니다."))
                        case .kProfileHEVCMain10:
                            Text(String(localized: "settings.projection.codec_sheet.profile.hevc_main10_description", defaultValue: "Main10 Profile을 사용합니다.\n10-bit 색상 지원으로 더 풍부한 색상을 제공합니다."))
                        default:
                            Text(String(localized: "settings.projection.codec_sheet.profile.description", defaultValue: "코덱 프로파일을 설정합니다."))
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
                        Text(String(localized: "settings.projection.codec_sheet.dynamic_range.sdr", defaultValue: "SDR (Standard Dynamic Range)"))
                            .tag(CodecOptionValue.kDynamicRangeSDR)

                        Text(String(localized: "settings.projection.codec_sheet.dynamic_range.hdr", defaultValue: "HDR (High Dynamic Range)"))
                            .tag(CodecOptionValue.kDynamicRangeHDR)
                    } label: {
                        Text(String(localized: "settings.projection.codec_sheet.dynamic_range.title", defaultValue: "다이나믹 레인지"))
                        switch specification.options[.dynamicRange] {
                        case .kDynamicRangeSDR:
                            Text(String(localized: "settings.projection.codec_sheet.dynamic_range.sdr_description", defaultValue: "표준 다이나믹 레인지를 사용합니다."))
                        case .kDynamicRangeHDR:
                            Text(String(localized: "settings.projection.codec_sheet.dynamic_range.hdr_description", defaultValue: "사용 가능한 경우 HDR 다이나믹 레인지를 사용합니다."))
                        default:
                            Text(String(localized: "settings.projection.codec_sheet.dynamic_range.description", defaultValue: "다이나믹 레인지를 설정합니다."))
                        }
                    }.disabled(!specification.isEligibleForHDR.isEligible)
                    
                    Slider(
                        value: .convert($specification.maximumResolutionLevel.rawValue),
                        in: 0...Double(CodecResolutionLevel.hd4k.rawValue),
                        step: 1,
                        minimumValueLabel: Text(String(localized: "settings.projection.codec_sheet.resolution.auto", defaultValue: "자동")),
                        maximumValueLabel: Text(String(localized: "settings.projection.codec_sheet.resolution.4k", defaultValue: "4K"))
                    ) {
                        Text(String(localized: "settings.projection.codec_sheet.resolution.title", defaultValue: "최대 해상도"))
                        if specification.maximumResolutionLevel == .unlimited {
                            Text(String(localized: "settings.projection.codec_sheet.resolution.auto_description", defaultValue: "클라이언트의 협상 내용을 기반으로 최대 해상도를 결정합니다."))
                        } else {
                            Text(String(localized: "settings.projection.codec_sheet.resolution.level_description", defaultValue: "최대 해상도를 \(specification.maximumResolutionLevel.displayText)으로 설정합니다."))
                        }
                    }
                    
                    Slider(
                        value: $specification.frameRate,
                        in: 0...60,
                        step: 15,
                        minimumValueLabel: Text(String(localized: "settings.projection.codec_sheet.framerate.auto", defaultValue: "자동")),
                        maximumValueLabel: Text(String(localized: "settings.projection.codec_sheet.framerate.60fps", defaultValue: "60 FPS"))
                    ) {
                        Text(String(localized: "settings.projection.codec_sheet.framerate.title", defaultValue: "프레임 속도"))
                        if specification.frameRate == 0 {
                            Text(String(localized: "settings.projection.codec_sheet.framerate.auto_description", defaultValue: "클라이언트의 협상 내용을 기반으로 프레임 속도를 결정합니다."))
                        } else {
                            Text(String(localized: "settings.projection.codec_sheet.framerate.value_description", defaultValue: "프레임 속도를 최대 \(Int(specification.frameRate)) FPS로 설정합니다."))
                        }
                    }
                    
                    Picker(selection: $specification.options[.displayDensity]) {
                        Text(String(localized: "settings.projection.codec_sheet.display_density.auto", defaultValue: "자동"))
                            .tag(CodecOptionValue.kDisplayDensityAuto)

                        Text(String(localized: "settings.projection.codec_sheet.display_density.performance", defaultValue: "성능 우선"))
                            .tag(CodecOptionValue.kDisplayDensityPerformance)

                        Text(String(localized: "settings.projection.codec_sheet.display_density.best", defaultValue: "화질 우선"))
                            .tag(CodecOptionValue.kDisplayDensityBest)
                    } label: {
                        Text(String(localized: "settings.projection.codec_sheet.display_density.title", defaultValue: "디스플레이 밀도"))
                        switch specification.options[.displayDensity] {
                        case .kDisplayDensityAuto:
                            Text(String(localized: "settings.projection.codec_sheet.display_density.auto_description", defaultValue: "디스플레이 밀도를 자동으로 선택합니다."))
                        case .kDisplayDensityPerformance:
                            Text(String(localized: "settings.projection.codec_sheet.display_density.performance_description", defaultValue: "성능을 우선시하여 디스플레이 밀도를 설정합니다.\n대부분의 경우 1x 밀도로 설정됩니다."))
                        case .kDisplayDensityBest:
                            Text(String(localized: "settings.projection.codec_sheet.display_density.best_description", defaultValue: "HIDPI / Retina 디스플레이 밀도를 사용하려 노력합니다.\n더 나은 화질을 제공하지만, 높은 대역폭과 컴퓨팅 자원을 사용합니다."))

                        default:
                            Text(String(localized: "settings.projection.codec_sheet.display_density.description", defaultValue: "디스플레이 밀도를 설정합니다."))
                        }
                    }
                } header: {
                    Text(String(localized: "settings.projection.codec_sheet.header", defaultValue: "\(specification.displayTitle) 코덱 설정"))
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
    @ViewBuilder
    func h264ProfileOptions() -> some View {
        Text(String(localized: "settings.projection.codec_sheet.profile.h264_baseline", defaultValue: "Baseline Profile (가장 높은 호환성, 압축률 낮음)"))
            .tag(CodecOptionValue.kProfileH264Baseline)
        Text(String(localized: "settings.projection.codec_sheet.profile.h264_main", defaultValue: "Main Profile"))
            .tag(CodecOptionValue.kProfileH264Main)
        Text(String(localized: "settings.projection.codec_sheet.profile.h264_high", defaultValue: "High Profile (가장 낮은 호환성, 압축률 높음)"))
            .tag(CodecOptionValue.kProfileH264High)
    }

    @ViewBuilder
    func hevcProfileOptions() -> some View {
        Text(String(localized: "settings.projection.codec_sheet.profile.hevc_main", defaultValue: "Main Profile"))
            .tag(CodecOptionValue.kProfileHEVCMain)
        Text(String(localized: "settings.projection.codec_sheet.profile.hevc_main10", defaultValue: "Main10 Profile (10-bit 색상 지원)"))
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
