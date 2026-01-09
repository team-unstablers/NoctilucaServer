//
//  CodecSpecificationSheet.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation

import SwiftUI

import SiriusKit


struct MJPGCodecSpecificationSheet: View {
    let actionHandler: (CodecSpecificationSheetAction) -> Void
    
    @State
    var specification: CodecSpecification = .h264
    
    init(specification: CodecSpecification, actionHandler: @escaping (CodecSpecificationSheetAction) -> Void) {
        self.specification = specification
        self.actionHandler = actionHandler
    }
    
    @ViewBuilder
    var __body: some View {
        VStack {
            Form {
                Section {
                    Picker(selection: $specification.options[.tileSize]) {
                        Text("64x64")
                            .tag(CodecOptionValue.kTileSize64x64)
                        Text("128x128")
                            .tag(CodecOptionValue.kTileSize128x128)
                        Text("256x256")
                            .tag(CodecOptionValue.kTileSize256x256)
                    } label: {
                        Text("타일 크기")
                        switch specification.options[.tileSize] {
                        case .kTileSize64x64:
                            Text("타일 크기로 64x64를 사용합니다.\n해상도가 낮거나, 화면 변화가 적은 경우에 적합합니다.")
                        case .kTileSize128x128:
                            Text("타일 크기로 128x128를 사용합니다.\n대부분의 상황에서 균형 잡힌 성능을 제공합니다.")
                        case .kTileSize256x256:
                            Text("타일 크기로 256x256를 사용합니다.\n해상도가 높거나, 화면 변화가 많은 경우에 적합합니다.")
                        default:
                            Text("타일 크기를 설정합니다.")
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
                            Text("타일의 내용에 따라 최적의 색상 포맷을 자동으로 선택합니다.")
                        case .kColorFormatYUV420:
                            Text("YUV 4:2:0 색상 포맷을 사용합니다. 대부분의 기기에서 호환됩니다.")
                        case .kColorFormatYUV444:
                            Text("YUV 4:4:4 색상 포맷을 사용합니다.\n텍스트 가독성이 향상되지만, 대역폭 사용량이 늘어나고 호환성이 떨어질 수 있습니다.")
                        default:
                            Text("색상 포맷을 설정합니다.")
                        }
                    }
                    
                    Slider(
                        value: .convert($specification.options[.compressionLevel]),
                        in: 30...100,
                        step: 5,
                        minimumValueLabel: Text("30 (저화질)"),
                        maximumValueLabel: Text("100 (고화질)")
                    ) {
                        Text("JPEG 압축 품질")
                        if let compressionLevel = Int(specification.options[.compressionLevel]?.rawValue ?? "1") {
                            if compressionLevel == 100 {
                                Text("**무손실 압축을 사용합니다.** 매우 높은 화질을 제공하지만, 대역폭 사용량이 비정상적으로 증가합니다.")
                            } else if compressionLevel >= 70 {
                                Text("**원격 제어에서 통상적으로 사용되지 않는 높은 품질 \(compressionLevel)로 설정합니다.** 매우 높은 화질을 제공하지만, 대역폭 사용량이 증가합니다.")
                            } else {
                                Text("압축 품질을 \(compressionLevel)으로 설정합니다.")
                            }
                        }
                    }
                    
                    Toggle(isOn: .constant(false)) {
                        Text("상수 압축 품질 대신 양자화 테이블 사용 (작업 중)")
                        Text("DQT 및 자체 품질 결정 알고리즘을 사용하여 각 타일마다 적절한 압축 품질을 동적으로 결정합니다.")
                    }
                    .disabled(true)

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
                    Text("MJPG 코덱은 [타일 인코딩](https://google.com)을 사용합니다.\nNoctiluca Server의 MJPG 인코더는 [libjpeg-turbo](https://libjpeg-turbo.org/)를 사용하며, libjpeg-turbo의 공식 바이너리를 동봉하여 제공됩니다.")
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
    
    var body: some View {
        if specification.fourCC != .mjpg {
            Text("ASSERTION FAILED: This sheet is only for MJPG codec specification.")
        } else {
            __body
        }
    }
}

