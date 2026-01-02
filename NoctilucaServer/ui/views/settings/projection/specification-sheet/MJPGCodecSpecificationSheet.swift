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
                    Slider(
                        value: .convert($specification.options[.compressionLevel]),
                        in: 80...100,
                        step: 1,
                        minimumValueLabel: Text("80 (저화질)"),
                        maximumValueLabel: Text("100 (고화질)")
                    ) {
                        Text("JPEG 압축 품질")
                        if let compressionLevel = Int(specification.options[.compressionLevel]?.rawValue ?? "1") {
                            if compressionLevel == 100 {
                                Text("**무손실 압축을 사용합니다.** 매우 높은 화질을 제공하지만, 대역폭 사용량이 증가합니다.")
                            } else if compressionLevel >= 93 {
                                Text("**통상적으로 사용되지 않는 높은 품질 \(compressionLevel)로 설정합니다.** 매우 높은 화질을 제공하지만, 대역폭 사용량이 증가합니다.")
                            } else {
                                Text("압축 품질을 \(compressionLevel)으로 설정합니다.")
                            }
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
    
    var body: some View {
        if specification.fourCC != .mjpg {
            Text("ASSERTION FAILED: This sheet is only for MJPG codec specification.")
        } else {
            __body
        }
    }
}

