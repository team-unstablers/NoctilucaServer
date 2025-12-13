//
//  CodecSpecificationSheet.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation

import SwiftUI

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
                        Text("자동")
                            .tag(CodecOptionValue.kHardwareAccelerationTrue)
                        Text("사용 안 함")
                            .tag(CodecOptionValue.kHardwareAccelerationFalse)
                        Text("강제 사용")
                            .tag(CodecOptionValue.kHardwareAccelerationForced)
                    } label: {
                        Text("하드웨어 가속")
                        switch specification.options[.hardwareAcceleration] {
                        case .kHardwareAccelerationTrue:
                            Text("가능한 경우 하드웨어 가속을 사용합니다.")
                        case .kHardwareAccelerationFalse:
                            Text("하드웨어 가속을 사용하지 않고, 소프트웨어 압축만 사용합니다.\n컴퓨팅 자원이 부족해질 수 있습니다.")
                        case .kHardwareAccelerationForced:
                            Text("하드웨어 가속을 강제로 사용합니다.\n인코더 초기화에 실패하는 경우, 세션이 강제로 종료될 수 있습니다.")
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
                            Text("YUV 4:4:4 색상 포맷을 사용합니다.\n더 높은 색상 정확도를 제공하지만, 호환성이 떨어질 수 있습니다.")
                        default:
                            Text("색상 포맷을 설정합니다.")
                        }
                    }
                    
                    Picker(selection: $specification.options[.profile]) {
                        Text("자동")
                            .tag(CodecOptionValue.kProfileAuto)
                        Text("Baseline Profile (가장 높은 호환성, 압축률 낮음)")
                            .tag(CodecOptionValue.kProfileBaseline)
                        Text("Main Profile")
                            .tag(CodecOptionValue.kProfileMain)
                        Text("High Profile (가장 낮은 호환성, 압축률 높음)")
                            .tag(CodecOptionValue.kProfileHigh)
                    } label: {
                        Text("코덱 프로파일")
                        switch specification.options[.profile] {
                        case .kProfileAuto:
                            Text("최적의 코덱 프로파일을 자동으로 선택합니다.")
                        case .kProfileBaseline:
                            Text("호환성이 높은 Baseline Profile을 사용합니다.\n코덱의 고급 기능을 사용할 수 없기 때문에 압축률과 화질이 낮습니다.")
                        case .kProfileMain:
                            Text("Main Profile을 사용합니다.\n대부분의 기기에서 적절한 호환성과 압축률을 제공합니다.")
                        case .kProfileHigh:
                            Text("High Profile을 사용합니다.\n고급 기능을 사용하여 최고의 압축률과 화질을 제공합니다.")
                        default:
                            Text("코덱 프로파일을 설정합니다.")
                        }
                    }
                    
                    Slider(
                        value: .convert($specification.maximumResolutionLevel.rawValue),
                        in: 0...Double(CodecResolutionLevel.hd4k.rawValue),
                        step: 1,
                        minimumValueLabel: Text("자동"),
                        maximumValueLabel: Text("4K")
                    ) {
                        Text("최대 해상도")
                        if specification.maximumResolutionLevel == .unlimited {
                            Text("클라이언트의 협상 내용을 기반으로 최대 해상도를 결정합니다.")
                        } else {
                            Text("최대 해상도를 \(specification.maximumResolutionLevel.displayText)으로 설정합니다.")
                        }
                    }
                    
                    Slider(
                        value: $specification.frameRate,
                        in: 0...60,
                        step: 15,
                        minimumValueLabel: Text("자동"),
                        maximumValueLabel: Text("60 FPS")
                    ) {
                        Text("프레임 속도")
                        if specification.frameRate == 0 {
                            Text("클라이언트의 협상 내용을 기반으로 프레임 속도를 결정합니다.")
                        } else {
                            Text("프레임 속도를 최대 \(Int(specification.frameRate)) FPS로 설정합니다.")
                        }
                    }
                } header: {
                    Text("\(specification.displayTitle) 코덱 설정")
                }
            }
            .formStyle(.grouped)
            
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
}


