//
//  WebPCodecSpecificationSheet.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 2/8/26.
//

import Foundation

import SwiftUI

import SiriusKit


struct WebPCodecSpecificationSheet: View {
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
                    Picker(selection: $specification.options[.tileSize]) {
                        Text(markdown: String(localized: "settings.projection.webp_sheet.tile_size.64x64", defaultValue: "64x64"))
                            .tag(CodecOptionValue.kTileSize64x64)
                        Text(markdown: String(localized: "settings.projection.webp_sheet.tile_size.128x128", defaultValue: "128x128"))
                            .tag(CodecOptionValue.kTileSize128x128)
                        Text(markdown: String(localized: "settings.projection.webp_sheet.tile_size.256x256", defaultValue: "256x256"))
                            .tag(CodecOptionValue.kTileSize256x256)
                    } label: {
                        Text(markdown: String(localized: "settings.projection.webp_sheet.tile_size.title", defaultValue: "타일 크기"))
                        switch specification.options[.tileSize] {
                        case .kTileSize64x64:
                            Text(markdown: String(localized: "settings.projection.webp_sheet.tile_size.64x64_description", defaultValue: "타일 크기로 64x64를 사용합니다.\n해상도가 낮거나, 화면 변화가 적은 경우에 적합합니다."))
                        case .kTileSize128x128:
                            Text(markdown: String(localized: "settings.projection.webp_sheet.tile_size.128x128_description", defaultValue: "타일 크기로 128x128를 사용합니다.\n대부분의 상황에서 균형 잡힌 성능을 제공합니다."))
                        case .kTileSize256x256:
                            Text(markdown: String(localized: "settings.projection.webp_sheet.tile_size.256x256_description", defaultValue: "타일 크기로 256x256를 사용합니다.\n해상도가 높거나, 화면 변화가 많은 경우에 적합합니다."))
                        default:
                            Text(markdown: String(localized: "settings.projection.webp_sheet.tile_size.description", defaultValue: "타일 크기를 설정합니다."))
                        }
                    }

                    SettingsEntry(
                        title: String(localized: "settings.projection.webp_sheet.compression_quality.title", defaultValue: "WebP 압축 품질"),
                        subtitle: {
                            if let compressionLevel = Int(specification.options[.compressionLevel]?.rawValue ?? "80") {
                                if compressionLevel == 100 {
                                    return String(localized: "settings.projection.webp_sheet.compression_quality.lossless_subtitle", defaultValue: "무손실에 가까운 압축")
                                } else {
                                    return String(localized: "settings.projection.webp_sheet.compression_quality.value_subtitle", defaultValue: "압축 품질 \(compressionLevel)")
                                }
                            }
                            return ""
                        }()
                    ) {
                        Slider(
                            value: .convert($specification.options[.compressionLevel]),
                            in: 30...100,
                            step: 5,
                            minimumValueLabel: Text(markdown: String(localized: "settings.projection.webp_sheet.compression_quality.min", defaultValue: "30 (저화질)")),
                            maximumValueLabel: Text(markdown: String(localized: "settings.projection.webp_sheet.compression_quality.max", defaultValue: "100 (고화질)"))
                        ) {
                        }
                    }
                }

                Section {
                    SettingsEntry(
                        title: String(localized: "settings.projection.webp_sheet.resolution.title", defaultValue: "최대 해상도"),
                        subtitle: specification.maximumResolutionLevel == .unlimited ? (
                            String(localized: "settings.projection.webp_sheet.resolution.auto_description", defaultValue: "클라이언트의 협상 내용을 기반으로 최대 해상도를 결정합니다.")
                        ) : (
                            String(format: String(localized: "settings.projection.webp_sheet.resolution.level_description_format", defaultValue: "최대 해상도를 %@으로 제한합니다."), specification.maximumResolutionLevel.displayText)
                        )
                    ) {
                        Slider(
                            value: .convert($specification.maximumResolutionLevel.rawValue),
                            in: 0...Double(CodecResolutionLevel.hd4k.rawValue),
                            step: 1,
                            minimumValueLabel: Text(markdown: String(localized: "settings.projection.webp_sheet.resolution.auto", defaultValue: "자동")),
                            maximumValueLabel: Text("4K")
                        ) {
                        }
                    }

                    SettingsEntry(
                        title: String(localized: "settings.projection.webp_sheet.framerate.title", defaultValue: "프레임 속도"),
                        subtitle: specification.frameRate == 0 ? (
                            String(localized: "settings.projection.webp_sheet.framerate.auto_description", defaultValue: "클라이언트의 협상 내용을 기반으로 프레임 속도를 결정합니다.")
                        ) : (
                            String(format: String(localized: "settings.projection.webp_sheet.framerate.value_description_format", defaultValue: "프레임 속도를 최대 %d FPS로 제한합니다."), Int(specification.frameRate))
                        )
                    ) {
                        Slider(
                            value: $specification.frameRate,
                            in: 0...60,
                            step: 15,
                            minimumValueLabel: Text(markdown: String(localized: "settings.projection.webp_sheet.framerate.auto", defaultValue: "자동")),
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
    var advancedSettingsView: some View {
        VStack {
            Form {
                Section {
                    Picker(selection: $specification.options[.colorFormat]) {
                        Text(markdown: String(localized: "settings.projection.webp_sheet.color_format.auto", defaultValue: "자동"))
                            .tag(CodecOptionValue.kColorFormatAuto)
                        Text(markdown: String(localized: "settings.projection.webp_sheet.color_format.yuv420", defaultValue: "YUV 4:2:0"))
                            .tag(CodecOptionValue.kColorFormatYUV420)
                        Text(markdown: String(localized: "settings.projection.webp_sheet.color_format.yuv444", defaultValue: "YUV 4:4:4"))
                            .tag(CodecOptionValue.kColorFormatYUV444)
                    } label: {
                        Text(markdown: String(localized: "settings.projection.webp_sheet.color_format.title", defaultValue: "색상 포맷"))
                        switch specification.options[.colorFormat] {
                        case .kColorFormatAuto:
                            Text(markdown: String(localized: "settings.projection.webp_sheet.color_format.auto_description", defaultValue: "최적의 색상 포맷을 자동으로 선택합니다."))
                        case .kColorFormatYUV420:
                            Text(markdown: String(localized: "settings.projection.webp_sheet.color_format.yuv420_description", defaultValue: "YUV 4:2:0 색상 포맷을 사용합니다. 대부분의 기기에서 호환됩니다."))
                        case .kColorFormatYUV444:
                            Text(markdown: String(localized: "settings.projection.webp_sheet.color_format.yuv444_description", defaultValue: "YUV 4:4:4 색상 포맷을 사용합니다.\n텍스트 가독성이 향상되지만, 대역폭 사용량이 늘어나고 호환성이 떨어질 수 있습니다."))
                        default:
                            Text(markdown: String(localized: "settings.projection.webp_sheet.color_format.description", defaultValue: "색상 포맷을 설정합니다."))
                        }
                    }

                    Slider(
                        value: .convert($specification.options[.quantizeLevel]),
                        in: 0...5,
                        step: 1,
                        minimumValueLabel: Text(markdown: String(localized: "settings.projection.webp_sheet.quantize_level.min", defaultValue: "0 (없음)")),
                        maximumValueLabel: Text(markdown: String(localized: "settings.projection.webp_sheet.quantize_level.max", defaultValue: "5 (최대)"))
                    ) {
                        Text(markdown: String(localized: "settings.projection.webp_sheet.quantize_level.title", defaultValue: "양자화 레벨"))
                        if let quantizeLevel = Int(specification.options[.quantizeLevel]?.rawValue ?? "0") {
                            switch quantizeLevel {
                            case 0:
                                Text(markdown: String(localized: "settings.projection.webp_sheet.quantize_level.none_description", defaultValue: "양자화를 사용하지 않습니다. 원본 색상을 유지합니다."))
                            case 1:
                                Text(markdown: String(localized: "settings.projection.webp_sheet.quantize_level.light_description", defaultValue: "가벼운 양자화를 적용합니다. 색상 품질을 유지하면서 압축률을 약간 향상시킵니다."))
                            case 2:
                                Text(markdown: String(localized: "settings.projection.webp_sheet.quantize_level.medium_description", defaultValue: "중간 양자화를 적용합니다. 그라데이션 영역에서 압축률이 향상됩니다."))
                            case 3:
                                Text(markdown: String(localized: "settings.projection.webp_sheet.quantize_level.strong_description", defaultValue: "강한 양자화를 적용합니다. 압축률이 크게 향상되지만, 색상 밴딩이 발생할 수 있습니다."))
                            case 4:
                                Text(markdown: String(localized: "settings.projection.webp_sheet.quantize_level.very_strong_description", defaultValue: "매우 강한 양자화를 적용합니다. 눈에 띄는 색상 손실이 발생할 수 있습니다."))
                            case 5:
                                Text(markdown: String(localized: "settings.projection.webp_sheet.quantize_level.maximum_description", defaultValue: "최대 양자화를 적용합니다. 심각한 색상 손실이 발생하지만, 압축률이 극대화됩니다."))
                            default:
                                Text(markdown: String(localized: "settings.projection.webp_sheet.quantize_level.value_description", defaultValue: "양자화 레벨을 \(quantizeLevel)으로 설정합니다."))
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
                    Text(String(localized: "settings.projection.webp_sheet.tab.basic", defaultValue: "기본 설정"))
                }
            advancedSettingsView
                .tabItem {
                    Image(systemName: "gearshape.2.fill")
                    Text(String(localized: "settings.projection.webp_sheet.tab.advanced", defaultValue: "고급 설정"))
                }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack {
            if #available(macOS 15.0, *) {
                tabContent
                    .tabViewStyle(.sidebarAdaptable)
            } else {
                tabContent
            }

            HStack {
                Button(String(localized: "settings.projection.webp_sheet.cancel", defaultValue: "취소")) {
                    dismiss()
                }
                Button(String(localized: "settings.projection.webp_sheet.save", defaultValue: "저장")) {
                    onSave(specification)
                    dismiss()
                }
            }
            .padding(.bottom)
        }
    }
}
