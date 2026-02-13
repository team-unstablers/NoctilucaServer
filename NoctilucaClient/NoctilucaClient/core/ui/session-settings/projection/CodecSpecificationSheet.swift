//
//  CodecSpecificationSheet.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation

import SwiftUI

import SiriusKitClient

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
    
    @ViewBuilder
    var _body: some View {
        VStack {
            Form {
                Section {
                    Picker(selection: $specification.options[.hardwareAcceleration]) {
                        Text("자동")
                            .tag(CodecOptionValue.kHardwareAccelerationAuto)
                        Text("사용 안 함")
                            .tag(CodecOptionValue.kHardwareAccelerationFalse)
                    } label: {
                        Text("하드웨어 가속")
                        switch specification.options[.hardwareAcceleration] {
                        case .kHardwareAccelerationAuto:
                            Text("서버가 환경에 맞춰 하드웨어 가속 사용 여부를 자동으로 결정합니다.")
                        case .kHardwareAccelerationFalse:
                            Text("서버에게 하드웨어 가속 사용을 요청합니다.\n참고: 옵션 이름은 legacy 호환성 때문에 false로 표시됩니다.")
                        default:
                            Text("서버 인코딩의 하드웨어 가속 요청 정책을 설정합니다.")
                        }
                    }
                    
                    Picker(selection: $specification.options[.colorFormat]) {
                        Text("자동")
                            .tag(CodecOptionValue.kColorFormatAuto)
                        Text("YUV 4:2:0")
                            .tag(CodecOptionValue.kColorFormatYUV420)
                        Text("YUV 4:4:4")
                            .tag(CodecOptionValue.kColorFormatYUV444)
                    } label: {
                        Text("색상 포맷")
                        switch specification.options[.colorFormat] {
                        case .kColorFormatAuto:
                            Text("최적의 색상 포맷을 자동으로 선택합니다.")
                        case .kColorFormatYUV420:
                            Text("YUV 4:2:0 색상 포맷을 사용합니다. 대부분의 기기에서 호환됩니다.")
                        case .kColorFormatYUV444:
                            Text("YUV 4:4:4 색상 포맷을 사용합니다.\n텍스트 가독성이 향상되지만, 대역폭 사용량이 늘어나고 호환성이 떨어질 수 있습니다.")
                        default:
                            Text("색상 포맷을 설정합니다.")
                        }
                    }
                    
                    Picker(selection: $specification.options[.colorRange]) {
                        Text("제한됨")
                            .tag(CodecOptionValue.kColorRangeLimited)
                        
                        Text("전체")
                            .tag(CodecOptionValue.kColorRangeFull)
                    } label: {
                        Text("색상 범위")
                        switch specification.options[.colorRange] {
                        case .kColorRangeLimited:
                            let range = specification.options[.dynamicRange] == .kDynamicRangeHDR ? "(64~940)" : "(16~235)"
                            Text("제한된 색상 범위 \(range)를 사용합니다.")
                        case .kColorRangeFull:
                            let range = specification.options[.dynamicRange] == .kDynamicRangeHDR ? "(0~1023)" : "(0~255)"
                            Text("전체 색상 범위 \(range)를 사용합니다.\n색상 재현이 더 좋지만, 일부 기기에서 호환성 문제가 발생할 수 있습니다.")
                        default:
                            Text("색상 범위를 설정합니다.")
                        }
                    }
                    
                    Picker(selection: $specification.options[.profile]) {
                        Text("자동")
                            .tag(CodecOptionValue.kProfileAuto)
                        
                        if specification.fourCC == .avc1 {
                            h264ProfileOptions()
                        }
                        
                        if specification.fourCC == .hvc1 {
                            hevcProfileOptions()
                        }
                    } label: {
                        Text("코덱 프로파일")
                        switch specification.options[.profile] {
                        case .kProfileAuto:
                            Text("최적의 코덱 프로파일을 자동으로 선택합니다.")
                        case .kProfileH264Baseline:
                            Text("호환성이 높은 Baseline Profile을 사용합니다.\n코덱의 고급 기능을 사용할 수 없기 때문에 압축률과 화질이 낮습니다.")
                        case .kProfileH264Main:
                            Text("Main Profile을 사용합니다.\n대부분의 기기에서 적절한 호환성과 압축률을 제공합니다.")
                        case .kProfileH264High:
                            Text("High Profile을 사용합니다.\n고급 기능을 사용하여 최고의 압축률과 화질을 제공합니다.")
                        case .kProfileHEVCMain:
                            Text("Main Profile을 사용합니다.\n대부분의 기기에서 적절한 호환성과 압축률을 제공합니다.")
                        case .kProfileHEVCMain10:
                            Text("Main10 Profile을 사용합니다.\n10-bit 색상 지원으로 더 풍부한 색상을 제공합니다.")
                        default:
                            Text("코덱 프로파일을 설정합니다.")
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
                        Text("SDR (Standard Dynamic Range)")
                            .tag(CodecOptionValue.kDynamicRangeSDR)
                        
                        Text("HDR (High Dynamic Range)")
                            .tag(CodecOptionValue.kDynamicRangeHDR)
                    } label: {
                        Text("다이나믹 레인지")
                        switch specification.options[.dynamicRange] {
                        case .kDynamicRangeSDR:
                            Text("표준 다이나믹 레인지를 사용합니다.")
                        case .kDynamicRangeHDR:
                            Text("사용 가능한 경우 HDR 다이나믹 레인지를 사용합니다.")
                        default:
                            Text("다이나믹 레인지를 설정합니다.")
                        }
                    }.disabled(!specification.isEligibleForHDR.isEligible)
                    
                } header: {
#if os(macOS)
                    Text("\(specification.displayTitle) 코덱 설정")
#endif
                }
                
                Section {
                    SettingsEntry(
                        title: "최대 해상도",
                        subtitle: specification.maximumResolutionLevel == .unlimited ? (
                            "클라이언트의 협상 내용을 기반으로 최대 해상도를 결정합니다."
                        ) : (
                            "최대 해상도를 \(specification.maximumResolutionLevel.displayText)으로 설정합니다."
                        )
                    ) {
                        Slider(
                            value: .convert($specification.maximumResolutionLevel.rawValue),
                            in: 0...Double(CodecResolutionLevel.hd4k.rawValue),
                            step: 1,
                            minimumValueLabel: Text("자동"),
                            maximumValueLabel: Text("4K")
                        ) {
                        }
                    }
                }
                
                Section {
                    SettingsEntry(
                        title: "프레임 속도",
                        subtitle: specification.frameRate == 0 ? (
                            "클라이언트의 협상 내용을 기반으로 프레임 속도를 결정합니다."
                        ) : (
                            "프레임 속도를 최대 \(Int(specification.frameRate)) FPS로 설정합니다."
                        )
                    ) {
                        Slider(
                            value: $specification.frameRate,
                            in: 0...60,
                            step: 15,
                            minimumValueLabel: Text("자동"),
                            maximumValueLabel: Text("60 FPS")
                        ) {
                        }
                    }
                }
                
                Section {
                    Picker(selection: $specification.options[.displayDensity]) {
                        Text("자동")
                            .tag(CodecOptionValue.kDisplayDensityAuto)

                        Text("성능 우선")
                            .tag(CodecOptionValue.kDisplayDensityPerformance)

                        Text("화질 우선")
                            .tag(CodecOptionValue.kDisplayDensityBest)
                    } label: {
                        Text("디스플레이 밀도")
                        switch specification.options[.displayDensity] {
                        case .kDisplayDensityAuto:
                            Text("디스플레이 밀도를 자동으로 선택합니다.")
                        case .kDisplayDensityPerformance:
                            Text("성능을 우선시하여 디스플레이 밀도를 설정합니다.\n대부분의 경우 1x 밀도로 설정됩니다.")
                        case .kDisplayDensityBest:
                            Text("HIDPI / Retina 디스플레이 밀도를 사용하려 노력합니다.\n더 나은 화질을 제공하지만, 높은 대역폭과 컴퓨팅 자원을 사용합니다.")

                        default:
                            Text("디스플레이 밀도를 설정합니다.")
                        }
                    }
                }

                Section {
                    qualityPicker()
                    qualityParameters()
                } header: {
                    Text("품질")
                }
            }
            .formStyle(.grouped)
        }
    }
    
#if os(macOS)
    var body: some View {
        VStack {
            _body
            
            HStack {
                Button("취소") {
                    actionHandler(.cancel)
                }
                Button("저장") {
                    actionHandler(.save(specification))
                }
            }
            .padding(.bottom)
        }
        
    }
#elseif os(iOS)
    var body: some View {
        NavigationStack {
            _body
                .navigationTitle("\(specification.displayTitle) 코덱 설정")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("취소") {
                            actionHandler(.cancel)
                        }
                    }
                    
                    ToolbarItem(placement: .confirmationAction) {
                        Button("저장", role: .compatibleConfirm) {
                            actionHandler(.save(specification))
                        }
                    }
                }
        }
    }
#endif
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
            Text("자동")
                .tag(QualityModeTag.auto)

            if !isImageCodec {
                Text("고정 비트레이트 (CBR)")
                    .tag(QualityModeTag.constantBitrate)

                Text("가변 비트레이트 (VBR)")
                    .tag(QualityModeTag.variableBitrate)

                Text("고정 품질 (CQP/CRF)")
                    .tag(QualityModeTag.fixedQuality)

                Text("무손실")
                    .tag(QualityModeTag.lossless)
            }
        } label: {
            Text("품질 모드")
            qualityModeDescription()
        }
    }

    @ViewBuilder
    func qualityModeDescription() -> some View {
        switch specification.quality {
        case .auto:
            Text("서버가 네트워크 상태에 따라 자동으로 품질을 조절합니다.")
        case .constantBitrate:
            Text("고정 비트레이트로 안정적인 대역폭을 사용합니다.")
        case .variableBitrate:
            Text("가변 비트레이트로 품질과 대역폭의 균형을 맞춥니다.")
        case .fixedQuality:
            Text("고정 품질 계수를 사용하여 일정한 화질을 유지합니다.")
        case .lossless:
            Text("무손실 압축을 사용하여 품질 저하 없이 전송합니다.")
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
            Text("균형")
                .tag(AutoQualityMode.balancedPriority)
            Text("품질 우선")
                .tag(AutoQualityMode.qualityPriority)
            Text("성능 우선")
                .tag(AutoQualityMode.performancePriority)
        } label: {
            Text("자동 품질 전략")
            switch AutoQualityMode(rawValue: mode) {
            case .balancedPriority:
                Text("품질과 성능 간의 균형을 맞춥니다.")
            case .qualityPriority:
                Text("가능한 최고의 품질을 우선시합니다.")
            case .performancePriority:
                Text("가능한 최고의 성능을 우선시합니다.")
            default:
                Text("자동 품질 전략을 설정합니다.")
            }
        }
    }

    @ViewBuilder
    func constantBitrateParameters(bitrateKbps: Int32) -> some View {
        SettingsEntry(
            title: "비트레이트 (kbps)",
            subtitle: "목표 비트레이트: \(bitrateKbps) kbps"
        ) {
            TextField("비트레이트", value: constantBitrateBinding, format: .number)
                .multilineTextAlignment(.trailing)
#if os(macOS)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
#endif
        }
    }

    @ViewBuilder
    func variableBitrateParameters(targetBitrateKbps: Int32, maxBitrateKbps: Int32) -> some View {
        SettingsEntry(
            title: "목표 비트레이트 (kbps)",
            subtitle: "목표: \(targetBitrateKbps) kbps"
        ) {
            TextField("목표 비트레이트", value: variableBitrateTargetBinding, format: .number)
                .multilineTextAlignment(.trailing)
#if os(macOS)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
#endif
        }

        SettingsEntry(
            title: "최대 비트레이트 (kbps)",
            subtitle: "최대: \(maxBitrateKbps) kbps"
        ) {
            TextField("최대 비트레이트", value: variableBitrateMaxBinding, format: .number)
                .multilineTextAlignment(.trailing)
#if os(macOS)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
#endif
        }
    }

    @ViewBuilder
    func fixedQualityParameters(factor: Int32) -> some View {
        SettingsEntry(
            title: "품질 계수",
            subtitle: "현재 품질 계수: \(factor)"
        ) {
            Slider(
                value: fixedQualityFactorBinding,
                in: 0...100,
                step: 1,
                minimumValueLabel: Text("0"),
                maximumValueLabel: Text("100")
            ) {
            }
        }
    }

    @ViewBuilder
    func losslessQualityParameters(mode: UInt32) -> some View {
        Picker(selection: losslessQualityModeBinding) {
            Text("균형")
                .tag(LosslessQualityMode.balancedPriority)
            Text("속도 우선")
                .tag(LosslessQualityMode.speedPriority)
            Text("압축 우선")
                .tag(LosslessQualityMode.compressionPriority)
        } label: {
            Text("무손실 품질 모드")
            switch LosslessQualityMode(rawValue: mode) {
            case .balancedPriority:
                Text("성능과 압축률 간의 균형을 맞춥니다.")
            case .speedPriority:
                Text("성능을 우선시합니다. (압축률이 낮아질 수 있음)")
            case .compressionPriority:
                Text("압축률을 우선시합니다. (성능이 낮아질 수 있음)")
            default:
                Text("무손실 품질 모드를 설정합니다.")
            }
        }
    }

    @ViewBuilder
    func h264ProfileOptions() -> some View {
        Text("Baseline Profile (가장 높은 호환성, 압축률 낮음)")
            .tag(CodecOptionValue.kProfileH264Baseline)
        Text("Main Profile")
            .tag(CodecOptionValue.kProfileH264Main)
        Text("High Profile (가장 낮은 호환성, 압축률 높음)")
            .tag(CodecOptionValue.kProfileH264High)
    }

    @ViewBuilder
    func hevcProfileOptions() -> some View {
        Text("Main Profile")
            .tag(CodecOptionValue.kProfileHEVCMain)
        Text("Main10 Profile (10-bit 색상 지원)")
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
