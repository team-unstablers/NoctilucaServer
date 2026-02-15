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
            title: "코덱 우선순위 설정",
            description: "서버에서 사용할 코덱의 우선순위를 설정합니다. 클라이언트와의 협상 시, 우선순위가 높은 코덱부터 시도합니다.",
            emptyText: "(구성된 코덱이 없습니다)\n추가 버튼을 눌러 코덱을 등록하세요.",
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
#endif

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("코덱 우선순위 설정")
            Text("서버에서 사용할 코덱의 우선순위를 설정합니다. 클라이언트와의 협상 시, 우선순위가 높은 코덱부터 시도합니다.")
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
                emptyText: "(구성된 코덱이 없습니다)\n추가 버튼을 눌러 코덱을 등록하세요.",
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
            title: "High Efficiency Video Coding (H.265)",
            description: "H.264보다 더 높은 압축 효율을 제공하는 최신 비디오 코덱입니다."
        ),
        .init(
            specification: .h264,
            title: "Advanced Video Coding (H.264)",
            description: "가장 널리 사용되는 비디오 코덱입니다. 높은 호환성을 제공합니다."
        ),
        .init(
            specification: .webp,
            title: "Tiled WebP",
            description: "타일링된 WebP를 사용합니다.\nMJPG보다 압축 효율이 좋지만 리소스를 더 많이 사용합니다.\n가상 머신 환경에서 화면 변경이 잦은 컨텐츠를 표시해야 하는 경우 적합합니다."
        ),

        .init(
            specification: .mjpg,
            title: "Motion JPEG",
            description: "전통적인 원격 데스크톱 환경에서 사용되는 비디오 코덱입니다.\n가상 머신 환경에서 화면 변경이 잦은 컨텐츠를 표시해야 하는 경우 적합합니다."
        ),
        .init(
            specification: .zrle,
            title: "RLE + Zstd",
            description: "전통적인 원격 데스크톱 환경에서 사용되는 비트맵 기반 비디오 코덱입니다.\n가상 머신 환경에서 화면 변경이 적은 텍스트 위주의 컨텐츠를 표시해야 하는 경우 적합합니다."
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
                Text("코덱 선택")
                    .font(.title2.bold())
                Text("추가할 코덱 유형을 선택하세요.")
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
                Button("취소") {
                    dismiss()
                }
                Button("추가") {
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
