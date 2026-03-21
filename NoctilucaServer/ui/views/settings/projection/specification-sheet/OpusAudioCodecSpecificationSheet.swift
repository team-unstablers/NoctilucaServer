//
//  OpusAudioCodecSpecificationSheet.swift
//  NoctilucaServer
//
//  Created by Codex on 3/8/26.
//

import Foundation

import SwiftUI

import SiriusKit

struct OpusAudioCodecSpecificationSheet: View {
    let onSave: (AudioCodecSpecification) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State
    var specification: AudioCodecSpecification

    init(specification: AudioCodecSpecification, onSave: @escaping (AudioCodecSpecification) -> Void) {
        _specification = State(initialValue: specification)
        self.onSave = onSave
    }

    // MARK: - Body

    var body: some View {
        VStack {
            Form {
                Section {
                    SettingsEntry(
                        title: String(localized: "settings.projection.opus_sheet.bitrate.title", defaultValue: "비트레이트"),
                        subtitle: String(
                            localized: "settings.projection.opus_sheet.bitrate.value",
                            defaultValue: "\(specification.bitrateKbps)kbps"
                        )
                    ) {
                        Slider(
                            value: bitrateBinding,
                            in: 32...256,
                            step: 32,
                            minimumValueLabel: Text("32kbps"),
                            maximumValueLabel: Text("256kbps")
                        ) {
                        }
                    }
                    /*
                    Picker(selection: $specification.frameSizeMs) {
                        Text("20ms")
                            .tag(Int32(20))
                        Text("40ms")
                            .tag(Int32(40))
                        Text("80ms")
                            .tag(Int32(80))
                    } label: {
                        Text(String(localized: "settings.projection.opus_sheet.frame_size.title", defaultValue: "프레임 사이즈"))
                        switch specification.frameSizeMs {
                        case 20:
                            Text(String(localized: "settings.projection.opus_sheet.frame_size.20ms_description", defaultValue: "낮은 지연 시간을 제공합니다."))
                        case 40:
                            Text(String(localized: "settings.projection.opus_sheet.frame_size.40ms_description", defaultValue: "지연 시간과 대역폭 사이의 균형을 제공합니다."))
                        case 80:
                            Text(String(localized: "settings.projection.opus_sheet.frame_size.80ms_description", defaultValue: "대역폭을 절약합니다. 지연 시간이 늘어날 수 있습니다."))
                        default:
                            Text(String(localized: "settings.projection.opus_sheet.frame_size.description", defaultValue: "프레임 사이즈를 설정합니다."))
                        }
                    }
                     */
                } header: {
                    Text("Opus")
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(String(localized: "settings.projection.codec_sheet.cancel", defaultValue: "취소")) {
                    dismiss()
                }
                Button(String(localized: "settings.projection.codec_sheet.save", defaultValue: "저장")) {
                    onSave(specification)
                    dismiss()
                }
            }
            .padding(.bottom)
        }
        .frame(minWidth: 400, minHeight: 200)
    }
}

// MARK: - Bindings

private extension OpusAudioCodecSpecificationSheet {
    var bitrateBinding: Binding<Double> {
        Binding<Double>(
            get: { Double(specification.bitrateKbps) },
            set: { specification.bitrateKbps = Int32($0) }
        )
    }
}
