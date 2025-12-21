//
//  AddressBarCandidateBox.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/21/25.
//

import SwiftUI

struct AddressBarCandidateItemView: View {
    let candidate: EndpointKind
    let query: String
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(candidate.displayText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(isFocused ? Color.white : Color.primary)
                .padding(.bottom, 4)
            
            HStack(spacing: 4) {
                if case .contact(let item) = candidate {
                    Text(item.endpointURL)
                        .foregroundColor(isFocused ? Color.white.opacity(0.8) : Color.secondary)
                    
                    Text("— 연락처에 등록된 컴퓨터")
                        .foregroundColor(isFocused ? Color.white.opacity(0.6) : Color.secondary)
                }
                if case .quickConnect(let endpointURL) = candidate {
                    Text("기본 설정을 사용하여 \(endpointURL) 으로 빠르게 연결하기")
                        .foregroundColor(isFocused ? Color.white.opacity(0.8) : Color.secondary)
                }
                if case .connect(let endpointURL) = candidate {
                    Text("설정 검토 후 \(endpointURL) 으로 연결하기")
                        .foregroundColor(isFocused ? Color.white.opacity(0.8) : Color.secondary)
                }
            }
            .font(.subheadline)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(isFocused ? Color.accentColor : Color.clear)
        .clipShape(.rect(cornerRadius: 12))
        .contentShape(.rect(cornerRadius: 12))
    }
}

struct AddressBarCandidateBox: View {
    let candidates: [EndpointKind]
    
    let focusedIndex: Int?
    let onHoverIndex: ((Int, Bool) -> Void)?
    let onSelectIndex: ((Int) -> Void)?
    
    let query = "con"
    
    var body: some View {
        VStack {
            ForEach(0..<candidates.count, id: \.self) { index in
                let candidate = candidates[index]
                
                AddressBarCandidateItemView(
                    candidate: candidate,
                    query: query,
                    isFocused: index == focusedIndex
                )
                .onHover { isHovering in
                    onHoverIndex?(index, isHovering)
                }
                .onTapGesture {
                    onSelectIndex?(index)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        }
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.2), radius: 10, x: 0, y: 4)
    }
}
