//
//  AudioCodecSpecificationListContainer.swift
//  NoctilucaClient
//
//  Created by Codex on 1/30/26.
//

import Foundation
import SwiftUI
import SiriusKitClient

enum AudioCodecSpecificationSheetAction {
    case save(AudioCodecSpecification)
    case cancel
}

struct AudioCodecSpecificationSheet: View {
    let actionHandler: (AudioCodecSpecificationSheetAction) -> Void
    
    @State
    var specification: AudioCodecSpecification
    
    init(specification: AudioCodecSpecification, actionHandler: @escaping (AudioCodecSpecificationSheetAction) -> Void) {
        self._specification = State(initialValue: specification)
        self.actionHandler = actionHandler
    }
    
    var body: some View {
        VStack {
            Form {
                Section {
                    Text("이 코덱에는 설정할 수 있는 옵션이 없습니다.")
                        .foregroundStyle(.secondary)
                } header: {
                    Text(specification.displayTitle)
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
        .frame(minWidth: 300, minHeight: 200)
    }
}

struct AudioCodecSpecificationListContainer: View {
    @Binding
    var codecSpecifications: [AudioCodecSpecification]
    
    @State
    private var selection = Set<Int>()
    
    @State
    private var isEditSheetPresented = false
    
    @State
    private var isAddSheetPresented = false

    var body: some View {
        VStack(alignment: .leading) {
            VStack(alignment: .leading) {
                Text("오디오 코덱 우선순위 설정")
                Text("사용할 오디오 코덱의 우선순위를 설정합니다. 우선순위가 높은 코덱부터 서버와 협상을 시도합니다.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            VStack {
                List(selection: $selection) {
                    ForEach(codecSpecifications, id: \.self) { specification in
                        HStack {
                            AudioCodecSpecificationListEntry(specification: specification)
                            if (selection.first == specification.hashValue) {
                                Spacer()
                                Button("편집") {
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
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            }
            
            HStack {
                Spacer()
                Button("삭제", role: .destructive) {
                    removeSelected()
                }
                .disabled(selection.isEmpty)

                Button("추가") {
                    isAddSheetPresented = true
                }
            }
        }
        .sheet(isPresented: $isEditSheetPresented) {
            if let firstSelected = selection.first,
               let specification = codecSpecifications.first(where: { $0.hashValue == firstSelected }) {
                AudioCodecSpecificationSheet(specification: specification) { action in
                     if case .save(let newSpecification) = action {
                        if let index = codecSpecifications.firstIndex(of: specification) {
                            codecSpecifications[index] = newSpecification
                        }
                    }
                    isEditSheetPresented = false
                }
            }
        }
        .sheet(isPresented: $isAddSheetPresented) {
            AudioCodecSpecificationAddSheet { specification in
                if !codecSpecifications.contains(specification) {
                    codecSpecifications.append(specification)
                }
                isAddSheetPresented = false
            }
            .fixedSize()
        }
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
            title: "Opus",
            description: "높은 음질과 낮은 지연 시간을 제공하는 현대적인 오디오 코덱입니다."
        ),
        .init(
            specification: .pcmu,
            title: "G.711 u-law",
            description: "전통적인 전화망에서 사용되는 표준 코덱입니다. 호환성이 높습니다."
        ),
        .init(
            specification: .pcma,
            title: "G.711 a-law",
            description: "유럽 등지에서 주로 사용되는 G.711 변형입니다."
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
                Button("취소") {
                    dismiss()
                }
                Button("추가") {
                    guard let selected = selected else { return }
                    handler(selected.specification)
                }
            }
        }
        .padding()
        .frame(minWidth: 520, alignment: .topLeading)
    }
}
