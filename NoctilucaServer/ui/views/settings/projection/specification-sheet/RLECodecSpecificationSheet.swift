//
//  RLECodecSpecificationSheet.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/13/25.
//

import Foundation

import SwiftUI

import SiriusKit


struct RLECodecSpecificationSheet: View {
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
                Section {
                    SettingsEntry(
                        title: String(localized: "settings.projection.rle_sheet.compression_level.title", defaultValue: "Zstd 압축 레벨"),
                        subtitle: {
                            if let compressionLevel = Int(specification.options[.compressionLevel]?.rawValue ?? "1") {
                                if compressionLevel >= 20 {
                                    return String(localized: "settings.projection.rle_sheet.compression_level.ultra_subtitle", defaultValue: "Ultra (\(compressionLevel))")
                                } else {
                                    return String(localized: "settings.projection.rle_sheet.compression_level.value_subtitle", defaultValue: "압축 레벨 \(compressionLevel)")
                                }
                            }
                            return ""
                        }()
                    ) {
                        Slider(
                            value: .convert($specification.options[.compressionLevel]),
                            in: 1...22,
                            step: 1,
                            minimumValueLabel: Text(markdown: String(localized: "settings.projection.rle_sheet.compression_level.min", defaultValue: "1 (빠름)")),
                            maximumValueLabel: Text(markdown: String(localized: "settings.projection.rle_sheet.compression_level.max", defaultValue: "22 (느림)"))
                        ) {
                        }
                    }
                }

                Section {
                    SettingsEntry(
                        title: String(localized: "settings.projection.rle_sheet.resolution.title", defaultValue: "최대 해상도"),
                        subtitle: specification.maximumResolutionLevel == .unlimited ? (
                            String(localized: "settings.projection.rle_sheet.resolution.auto_description", defaultValue: "클라이언트의 협상 내용을 기반으로 최대 해상도를 결정합니다.")
                        ) : (
                            String(format: String(localized: "settings.projection.rle_sheet.resolution.level_description_format", defaultValue: "최대 해상도를 %@으로 제한합니다."), specification.maximumResolutionLevel.displayText)
                        )
                    ) {
                        Slider(
                            value: .convert($specification.maximumResolutionLevel.rawValue),
                            in: 0...Double(CodecResolutionLevel.hd4k.rawValue),
                            step: 1,
                            minimumValueLabel: Text(markdown: String(localized: "settings.projection.rle_sheet.resolution.auto", defaultValue: "자동")),
                            maximumValueLabel: Text("4K")
                        ) {
                        }
                    }

                    SettingsEntry(
                        title: String(localized: "settings.projection.rle_sheet.framerate.title", defaultValue: "프레임 속도"),
                        subtitle: specification.frameRate == 0 ? (
                            String(localized: "settings.projection.rle_sheet.framerate.auto_description", defaultValue: "클라이언트의 협상 내용을 기반으로 프레임 속도를 결정합니다.")
                        ) : (
                            String(format: String(localized: "settings.projection.rle_sheet.framerate.value_description_format", defaultValue: "프레임 속도를 최대 %d FPS로 제한합니다."), Int(specification.frameRate))
                        )
                    ) {
                        Slider(
                            value: $specification.frameRate,
                            in: 5...15,
                            step: 5,
                            minimumValueLabel: Text(markdown: String(localized: "settings.projection.rle_sheet.framerate.min", defaultValue: "5 FPS")),
                            maximumValueLabel: Text("15 FPS")
                        ) {
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    @ViewBuilder
    var advancedSettingsView: some View {
        VStack {
            Form {
                Section {
                    Picker(selection: $specification.options[.colorFormat]) {
                        Text(markdown: String(localized: "settings.projection.rle_sheet.color_format.rgb888", defaultValue: "RGB 8:8:8"))
                            .tag(CodecOptionValue.kColorFormatRGB888)
                        Text(markdown: String(localized: "settings.projection.rle_sheet.color_format.rgb565", defaultValue: "RGB 5:6:5"))
                            .tag(CodecOptionValue.kColorFormatRGB565)
                    } label: {
                        Text(markdown: String(localized: "settings.projection.rle_sheet.color_format.title", defaultValue: "색상 포맷"))
                        switch specification.options[.colorFormat] {
                        case .kColorFormatAuto:
                            Text(markdown: String(localized: "settings.projection.rle_sheet.color_format.auto_description", defaultValue: "최적의 색상 포맷을 자동으로 선택합니다."))
                        case .kColorFormatRGB888:
                            Text(markdown: String(localized: "settings.projection.rle_sheet.color_format.rgb888_description", defaultValue: "RGB 8:8:8 색상 포맷을 사용합니다.\n높은 색상 정확도를 제공하지만, 대역폭 사용량이 늘어납니다."))
                        case .kColorFormatRGB565:
                            Text(markdown: String(localized: "settings.projection.rle_sheet.color_format.rgb565_description", defaultValue: "RGB 5:6:5 색상 포맷을 사용합니다.\n대역폭 사용량을 줄이지만, 색상 정확도가 낮아질 수 있습니다."))
                        default:
                            Text(markdown: String(localized: "settings.projection.rle_sheet.color_format.description", defaultValue: "색상 포맷을 설정합니다."))
                        }
                    }

                    Slider(
                        value: .convert($specification.options[.quantizeLevel]),
                        in: 0...5,
                        step: 1,
                        minimumValueLabel: Text(markdown: String(localized: "settings.projection.rle_sheet.quantize_level.min", defaultValue: "0 (없음)")),
                        maximumValueLabel: Text(markdown: String(localized: "settings.projection.rle_sheet.quantize_level.max", defaultValue: "5 (최대)"))
                    ) {
                        Text(markdown: String(localized: "settings.projection.rle_sheet.quantize_level.title", defaultValue: "양자화 레벨"))
                        if let quantizeLevel = Int(specification.options[.quantizeLevel]?.rawValue ?? "2") {
                            switch quantizeLevel {
                            case 0:
                                Text(markdown: String(localized: "settings.projection.rle_sheet.quantize_level.none_description", defaultValue: "양자화를 사용하지 않습니다. 원본 색상을 유지합니다."))
                            case 1:
                                Text(markdown: String(localized: "settings.projection.rle_sheet.quantize_level.light_description", defaultValue: "가벼운 양자화를 적용합니다. 색상 품질을 유지하면서 압축률을 약간 향상시킵니다."))
                            case 2:
                                Text(markdown: String(localized: "settings.projection.rle_sheet.quantize_level.medium_description", defaultValue: "중간 양자화를 적용합니다. 그라데이션 영역에서 압축률이 향상됩니다."))
                            case 3:
                                Text(markdown: String(localized: "settings.projection.rle_sheet.quantize_level.strong_description", defaultValue: "강한 양자화를 적용합니다. 압축률이 크게 향상되지만, 색상 밴딩이 발생할 수 있습니다."))
                            case 4:
                                Text(markdown: String(localized: "settings.projection.rle_sheet.quantize_level.very_strong_description", defaultValue: "매우 강한 양자화를 적용합니다. 눈에 띄는 색상 손실이 발생할 수 있습니다."))
                            case 5:
                                Text(markdown: String(localized: "settings.projection.rle_sheet.quantize_level.maximum_description", defaultValue: "최대 양자화를 적용합니다. 심각한 색상 손실이 발생하지만, 압축률이 극대화됩니다."))
                            default:
                                Text(markdown: String(localized: "settings.projection.rle_sheet.quantize_level.value_description", defaultValue: "양자화 레벨을 \(quantizeLevel)으로 설정합니다."))
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    var tabContent: some View {
        TabView {
            basicSettingsView
                .tabItem {
                    Image(systemName: "videoprojector.fill")
                    Text(String(localized: "settings.projection.rle_sheet.tab.basic", defaultValue: "기본 설정"))
                }
            advancedSettingsView
                .tabItem {
                    Image(systemName: "gearshape.2.fill")
                    Text(String(localized: "settings.projection.rle_sheet.tab.advanced", defaultValue: "고급 설정"))
                }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack {
            tabContent
                .tabViewStyle(.sidebarAdaptable)

            HStack {
                Button(String(localized: "settings.projection.rle_sheet.cancel", defaultValue: "취소")) {
                    dismiss()
                }
                Button(String(localized: "settings.projection.rle_sheet.save", defaultValue: "저장")) {
                    onSave(specification)
                    dismiss()
                }
            }
            .padding(.bottom)
        }
    }
}
