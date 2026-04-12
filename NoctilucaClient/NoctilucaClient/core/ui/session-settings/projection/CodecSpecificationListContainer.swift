//
//  AuthMethodContainer.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(Collaboration)
import Collaboration
#endif
import SwiftUI

import SiriusKitClient

struct CodecSpecificationListContainer: View {
    @Binding
    var codecSpecifications: [CodecSpecification]

    @State
    private var selection = Set<CodecSpecification>()

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
            title: String(localized: "session-settings.projection.codec_list.title", defaultValue: "코덱 우선순위 설정"),
            description: String(localized: "session-settings.projection.codec_list.description", defaultValue: "서버에서 사용할 코덱의 우선순위를 설정합니다. 클라이언트와의 협상 시, 우선순위가 높은 코덱부터 시도합니다."),
            emptyText: String(localized: "session-settings.projection.codec_list.empty", defaultValue: "(구성된 코덱이 없습니다)\n추가 버튼을 눌러 코덱을 등록하세요."),
            rowContent: { specification in
                CodecSpecificationListEntry(specification: specification)
            },
            addSheet: { onComplete in
                CodecSpecificationAddSheet { specification in
                    onComplete(specification)
                }
            },
            editSheet: { specification, onSave in
                Group {
                    switch specification.fourCC {
                    case .vp80:
                        VP8CodecSpecificationSheet(specification: specification) { newSpecification in
                            onSave(newSpecification)
                        }
                    default:
                        CodecSpecificationSheet(specification: specification) { newSpecification in
                            onSave(newSpecification)
                        }
                    }
                }
            }
        )
    }
#endif

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(markdown: String(localized: "session-settings.projection.codec_list.title", defaultValue: "코덱 우선순위 설정"))
            Text(markdown: String(localized: "session-settings.projection.codec_list.description", defaultValue: "서버에서 사용할 코덱의 우선순위를 설정합니다. 클라이언트와의 협상 시, 우선순위가 높은 코덱부터 시도합니다."))
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
                emptyText: String(localized: "session-settings.projection.codec_list.empty", defaultValue: "(구성된 코덱이 없습니다)\n추가 버튼을 눌러 코덱을 등록하세요."),
                rowContent: { specification in
                    CodecSpecificationListEntry(specification: specification)
                },
                addSheet: { onComplete in
                    CodecSpecificationAddSheet { specification in
                        onComplete(specification)
                    }
                },
                editSheet: { specification, onSave in
                    CodecSpecificationSheet(specification: specification) { newSpecification in
                        onSave(newSpecification)
                    }
                }
            )
        }
        .frame(maxWidth: .infinity)
    }
}

private struct CodecSpecificationAddTemplateRow: View {
    let specification: CodecSpecification

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
                // .foregroundStyle(.accentColor)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .focusable(true)
    }
}

struct CodecSpecificationAddSheet: View {
    struct Template: Hashable, Equatable {
        let specification: CodecSpecification
        let title: String
        let description: String

        func hash(into hasher: inout Hasher) {
            hasher.combine(specification)
        }
    }

    static let templates: [Template] = [
        .init(
            specification: .hevc,
            title: String(localized: "session-settings.projection.codec_list.template.hevc.title", defaultValue: "High Efficiency Video Coding (H.265)"),
            description: String(localized: "session-settings.projection.codec_list.template.hevc.description", defaultValue: "H.264보다 더 높은 압축 효율을 제공하는 최신 비디오 코덱입니다.")
        ),
        .init(
            specification: .h264,
            title: String(localized: "session-settings.projection.codec_list.template.h264.title", defaultValue: "Advanced Video Coding (H.264)"),
            description: String(localized: "session-settings.projection.codec_list.template.h264.description", defaultValue: "가장 널리 사용되는 비디오 코덱입니다. 높은 호환성을 제공합니다.")
        ),
        .init(
            specification: .vp8,
            title: String(localized: "settings.projection.codec_add.vp8.title", defaultValue: "VP8"),
            description: String(localized: "settings.projection.codec_add.vp8.description", defaultValue: "Google에서 개발한 자유로운(free) 비디오 코덱입니다. H.264와 유사한 압축 효율을 제공합니다.\n호스트가 가상 머신인 경우 적합합니다.")
        ),
    ]

    let handler: (CodecSpecification) -> Void

    @Environment(\.dismiss)
    private var dismiss

    @State
    var selected: Template? = Self.templates.first

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading) {
                Text(markdown: String(localized: "session-settings.projection.codec_list.add.title", defaultValue: "코덱 선택"))
                    .font(.title2.bold())
                Text(markdown: String(localized: "session-settings.projection.codec_list.add.description", defaultValue: "추가할 코덱 유형을 선택하세요."))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Self.templates, id: \.self) { template in
                    Button {
                        selected = template
                    } label: {
                        CodecSpecificationAddTemplateRow(
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
                // .disabled(!canCommitSelection)
            }
        }
        .padding()
#if os(macOS)
        .frame(minWidth: 520, alignment: .topLeading)
#endif
    }
}
