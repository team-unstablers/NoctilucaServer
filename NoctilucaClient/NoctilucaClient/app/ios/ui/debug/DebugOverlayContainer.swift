//
//  DebugOverlayContainer.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 4/3/26.
//

#if os(iOS)
import SwiftUI

/// iOS에서 디버그 뷰를 드래그 가능한 오버레이로 표시합니다.
struct DebugOverlayContainer: View {
    @ObservedObject var viewModel: RemoteSessionDebugViewModel

    @State private var isExpanded = false
    @State private var position: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    private var currentOffset: CGSize {
        CGSize(
            width: position.width + dragOffset.width,
            height: position.height + dragOffset.height
        )
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedView
            } else {
                compactView
            }
        }
        .contentShape(Rectangle())
        .offset(currentOffset)
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
        )
        .gesture(
            DragGesture(minimumDistance: 5)
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    position.width += value.translation.width
                    position.height += value.translation.height
                }
        )
    }

    private var compactView: some View {
        HStack(spacing: 6) {
            Image(systemName: "ant.fill")
                .font(.caption)
            Text("Debug")
                .font(.caption.bold())
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
    }

    private var expandedView: some View {
        RemoteSessionDebugView(viewModel: viewModel)
            .frame(width: 350, height: 480)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
            )
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
    }
}
#endif
