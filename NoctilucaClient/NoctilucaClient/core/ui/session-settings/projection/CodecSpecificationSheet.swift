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
                            Text("가능한 경우 하드웨어 가속을 사용합니다.")
                        case .kHardwareAccelerationFalse:
                            Text("하드웨어 가속을 사용하지 않고, 소프트웨어 압축만 사용합니다.\n컴퓨팅 자원이 부족해질 수 있습니다.")
                        default:
                            Text("하드웨어 가속 사용 여부를 설정합니다.")
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
