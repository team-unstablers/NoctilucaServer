//
//  AddContactTileView.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/12/26.
//

import SwiftUI

struct AddContactTileView: View {
    let onTap: () -> Void

    @State
    private var isHovering: Bool = false

    var body: some View {
        Button {
            onTap()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)

                Text("새 호스트 추가")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, minHeight: 100)
            .padding(12)
            .contentShape(.rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                    .foregroundStyle(.tertiary)
            }
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .brightness(isHovering ? 0.1 : 0.0)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

#Preview {
    HStack {
        AddContactTileView {}
    }
    .padding()
}
