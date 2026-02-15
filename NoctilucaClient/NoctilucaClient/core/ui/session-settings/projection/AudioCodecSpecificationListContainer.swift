//
//  AudioCodecSpecificationListContainer.swift
//  NoctilucaClient
//
//  Created by Codex on 1/30/26.
//

import Foundation
import SwiftUI
import SiriusKitClient

struct AudioCodecSpecificationSheet: View {
    let onSave: (AudioCodecSpecification) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State
    var specification: AudioCodecSpecification

    init(specification: AudioCodecSpecification, onSave: @escaping (AudioCodecSpecification) -> Void) {
        self._specification = State(initialValue: specification)
        self.onSave = onSave
    }

    var body: some View {
        VStack {
            Form {
                Section {
                    Text(String(localized: "session-settings.projection.audio_codec_list.no_options", defaultValue: "이 코덱에는 설정할 수 있는 옵션이 없습니다."))
                        .foregroundStyle(.secondary)
                } header: {
                    Text(specification.displayTitle)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button(String(localized: "common.cancel", defaultValue: "취소")) {
                    dismiss()
                }
                Button(String(localized: "common.save", defaultValue: "저장")) {
                    onSave(specification)
                }
            }
            .padding(.bottom)
        }
        .frame(minWidth: 300, minHeight: 200)
    }
}

struct AudioCodecSpecificationListContainer: View {
    @Binding
    var codecSpecifications: [AudioCodecSpecification]

    @State
    private var selection = Set<AudioCodecSpecification>()

    var body: some View {
#if os(macOS)
        macOSBody
#else
        iOSBody
#endif
    }

#if os(macOS)
    @ViewBuilder
    private var macOSBody: some View {
        EditableList(
            items: $codecSpecifications,
            id: \.self,
            selection: $selection,
            title: String(localized: "session-settings.projection.audio_codec_list.title", defaultValue: "오디오 코덱 우선순위 설정"),
            description: String(localized: "session-settings.projection.audio_codec_list.description", defaultValue: "사용할 오디오 코덱의 우선순위를 설정합니다. 우선순위가 높은 코덱부터 서버와 협상을 시도합니다."),
            emptyText: String(localized: "session-settings.projection.audio_codec_list.empty", defaultValue: "(구성된 코덱이 없습니다)\n추가 버튼을 눌러 코덱을 등록하세요."),
            rowContent: { specification in
                AudioCodecSpecificationListEntry(specification: specification)
            },
            addSheet: { onComplete in
                AudioCodecSpecificationAddSheet { specification in
                    onComplete(specification)
                }
                .fixedSize()
            },
            editSheet: { specification, onSave in
                AudioCodecSpecificationSheet(specification: specification) { newSpecification in
                    onSave(newSpecification)
                }
            }
        )
    }
#endif

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "session-settings.projection.audio_codec_list.title", defaultValue: "오디오 코덱 우선순위 설정"))
            Text(String(localized: "session-settings.projection.audio_codec_list.description", defaultValue: "사용할 오디오 코덱의 우선순위를 설정합니다. 우선순위가 높은 코덱부터 서버와 협상을 시도합니다."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var iOSBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerView
                .padding(.bottom, 12)

            Divider()

            EditableList(
                items: $codecSpecifications,
                id: \.self,
                selection: $selection,
                title: nil,
                description: nil,
                emptyText: String(localized: "session-settings.projection.audio_codec_list.empty", defaultValue: "(구성된 코덱이 없습니다)\n추가 버튼을 눌러 코덱을 등록하세요."),
                rowContent: { specification in
                    AudioCodecSpecificationListEntry(specification: specification)
                },
                addSheet: { onComplete in
                    AudioCodecSpecificationAddSheet { specification in
                        onComplete(specification)
                    }
                    .fixedSize()
                },
                editSheet: { specification, onSave in
                    AudioCodecSpecificationSheet(specification: specification) { newSpecification in
                        onSave(newSpecification)
                    }
                }
            )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AudioCodecSpecificationAddTemplateRow: View {
    let specification: AudioCodecSpecification
    let title: String
    let description: String
    let isSelected: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .focusable(true)
    }
}

struct AudioCodecSpecificationAddSheet: View {
    struct Template: Hashable, Equatable {
        let specification: AudioCodecSpecification
        let title: String
        let description: String

        func hash(into hasher: inout Hasher) {
            hasher.combine(specification)
        }
    }

    static let templates: [Template] = [
        .init(
            specification: .opus,
            title: String(localized: "session-settings.projection.audio_codec_list.template.opus.title", defaultValue: "Opus"),
            description: String(localized: "session-settings.projection.audio_codec_list.template.opus.description", defaultValue: "높은 음질과 낮은 지연 시간을 제공하는 현대적인 오디오 코덱입니다.")
        ),
        .init(
            specification: .pcmu,
            title: String(localized: "session-settings.projection.audio_codec_list.template.pcmu.title", defaultValue: "G.711 u-law"),
            description: String(localized: "session-settings.projection.audio_codec_list.template.pcmu.description", defaultValue: "전통적인 전화망에서 사용되는 표준 코덱입니다. 호환성이 높습니다.")
        ),
        .init(
            specification: .pcma,
            title: String(localized: "session-settings.projection.audio_codec_list.template.pcma.title", defaultValue: "G.711 a-law"),
            description: String(localized: "session-settings.projection.audio_codec_list.template.pcma.description", defaultValue: "유럽 등지에서 주로 사용되는 G.711 변형입니다.")
        )
    ]

    let handler: (AudioCodecSpecification) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State
    var selected: Template? = Self.templates.first

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading) {
                Text(String(localized: "session-settings.projection.audio_codec_list.add.title", defaultValue: "코덱 선택"))
                    .font(.title2.bold())
                Text(String(localized: "session-settings.projection.audio_codec_list.add.description", defaultValue: "추가할 코덱 유형을 선택하세요."))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.templates, id: \.self) { template in
                    Button {
                        selected = template
                    } label: {
                        AudioCodecSpecificationAddTemplateRow(
                            specification: template.specification,
                            title: template.title,
                            description: template.description,
                            isSelected: selected == template
                        )
                    }
                    .focusable(true)
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            HStack {
                Spacer()
                Button(String(localized: "common.cancel", defaultValue: "취소")) {
                    dismiss()
                }
                Button(String(localized: "common.add", defaultValue: "추가")) {
                    guard let selected = selected else { return }
                    handler(selected.specification)
                }
            }
        }
        .padding()
        .frame(minWidth: 520, alignment: .topLeading)
    }
}
