//
//  AuthMethodContainer.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/4/25.
//

import Foundation
import AppKit
#if canImport(Collaboration)
import Collaboration
#endif
import SwiftUI

import SiriusKit

struct CodecSpecificationListContainer: View {
    @Binding
    var codecSpecifications: [CodecSpecification]
    
    @State
    private var selection = Set<Int>()
    
    @State
    private var isEditSheetPresented = false
    
    @State
    private var isAddSheetPresented = false

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                Text(String(localized: "settings.projection.codec_priority.title", defaultValue: "코덱 우선순위 설정"))
                Text(String(localized: "settings.projection.codec_priority.description", defaultValue: "서버에서 사용할 코덱의 우선순위를 설정합니다. 클라이언트와의 협상 시, 우선순위가 높은 코덱부터 시도합니다."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack {
                List(selection: $selection) {
                    ForEach(codecSpecifications, id: \.self) { specification in
                        HStack {
                            CodecSpecificationListEntry(specification: specification)
                            if (selection.first == specification.hashValue) {
                                Spacer()
                                Button(String(localized: "settings.projection.codec_priority.edit", defaultValue: "편집")) {
                                    isEditSheetPresented = true
                                }
                            }
                        }
                            .tag(specification.hashValue)
                            .focusable(true)
                    }
                    .onMove(perform: moveCodecSpecification)
                }
                .listStyle(.inset)
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
            }
            
            HStack {
                Spacer()
                Button(String(localized: "settings.projection.codec_priority.delete", defaultValue: "삭제"), role: .destructive) {
                    removeSelected()
                }
                .disabled(selection.isEmpty)

                Button(String(localized: "settings.projection.codec_priority.add", defaultValue: "추가")) {
                    isAddSheetPresented = true
                }
            }
        }
        .sheet(isPresented: $isEditSheetPresented) {
            if let firstSelected = selection.first,
               let specification = codecSpecifications.first(where: { $0.hashValue == firstSelected }) {
                switch specification.fourCC {
                case .zrle:
                    RLECodecSpecificationSheet(specification: specification) { action in
                        if case .save(let newSpecification) = action {
                            if let index = codecSpecifications.firstIndex(of: specification) {
                                codecSpecifications[index] = newSpecification
                            }
                        }
                        isEditSheetPresented = false
                    }
                case .mjpg:
                    MJPGCodecSpecificationSheet(specification: specification) { action in
                        if case .save(let newSpecification) = action {
                            if let index = codecSpecifications.firstIndex(of: specification) {
                                codecSpecifications[index] = newSpecification
                            }
                        }
                        isEditSheetPresented = false
                    }
                default:
                    CodecSpecificationSheet(specification: specification) { action in
                        if case .save(let newSpecification) = action {
                            if let index = codecSpecifications.firstIndex(of: specification) {
                                codecSpecifications[index] = newSpecification
                            }
                        }
                        isEditSheetPresented = false
                    }
                }
            }
        }
        .sheet(isPresented: $isAddSheetPresented) {
            CodecSpecificationAddSheet { specification in
                if !codecSpecifications.contains(specification) {
                    codecSpecifications.append(specification)
                }
                isAddSheetPresented = false
            }
        }
        

        
        /*
        if let selected = selection.first,
           let handle = pluginRegistry.bundles[selected]
        {
            PluginBundleDetailView(metadata: handle.metadata)
        }
         */
    }
    
    
    private func moveCodecSpecification(from source: IndexSet, to destination: Int) {
        codecSpecifications.move(fromOffsets: source, toOffset: destination)
    }
    
    private func removeSelected() {
        guard !selection.isEmpty else { return }
        codecSpecifications.removeAll { selection.contains($0.hashValue) }
        selection.removeAll()
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
            title: String(localized: "settings.projection.codec_add.hevc.title", defaultValue: "High Efficiency Video Coding (H.265)"),
            description: String(localized: "settings.projection.codec_add.hevc.description", defaultValue: "H.264보다 더 높은 압축 효율을 제공하는 최신 비디오 코덱입니다.")
        ),
        .init(
            specification: .h264,
            title: String(localized: "settings.projection.codec_add.h264.title", defaultValue: "Advanced Video Coding (H.264)"),
            description: String(localized: "settings.projection.codec_add.h264.description", defaultValue: "가장 널리 사용되는 비디오 코덱입니다. 높은 호환성을 제공합니다.")
        ),
        .init(
            specification: .mjpg,
            title: String(localized: "settings.projection.codec_add.mjpg.title", defaultValue: "Motion JPEG"),
            description: String(localized: "settings.projection.codec_add.mjpg.description", defaultValue: "전통적인 원격 데스크톱 환경에서 사용되는 비디오 코덱입니다.\nRLE보다 압축 효율이 높지만 리소스를 더 많이 사용합니다.\n가상 머신 환경에서 화면 변경이 잦은 컨텐츠를 표시해야 하는 경우 적합합니다.")
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
                Text(String(localized: "settings.projection.codec_add.title", defaultValue: "코덱 선택"))
                    .font(.title2.bold())
                Text(String(localized: "settings.projection.codec_add.description", defaultValue: "추가할 코덱 유형을 선택하세요."))
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
                Button(String(localized: "settings.projection.codec_add.cancel", defaultValue: "취소")) {
                    dismiss()
                }
                Button(String(localized: "settings.projection.codec_add.add", defaultValue: "추가")) {
                    guard let selected = selected else { return }
                    handler(selected.specification)
                }
                // .disabled(!canCommitSelection)
            }
        }
        .padding()
        .frame(minWidth: 520, alignment: .topLeading)
    }
}
