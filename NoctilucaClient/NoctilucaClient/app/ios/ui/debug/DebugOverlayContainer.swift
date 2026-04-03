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

    @State private var isVisible = true
    @State private var isExpanded = true
    @State private var position: CGSize = .zero
    @State private var contentSize = CGSize(width: 380, height: 420)
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var resizeOffset: CGSize = .zero

    private let minWidth: CGFloat = 360
    private let minHeight: CGFloat = 300
    
    private var currentOffset: CGSize {
        CGSize(
            width: position.width + dragOffset.width,
            height: position.height + dragOffset.height
        )
    }

    private var currentSize: CGSize {
        CGSize(
            width: max(minWidth, contentSize.width + resizeOffset.width),
            height: max(minHeight, contentSize.height + resizeOffset.height)
        )
    }

    var body: some View {
        if isVisible {
            RingoOSDialog(
                title: "Debug",
                isExpanded: isExpanded,
                onClose: { withAnimation(.easeOut(duration: 0.15)) { isVisible = false } },
                onMaximize: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }
            ) {
                ZStack(alignment: .bottomTrailing) {
                    RemoteSessionDebugView(viewModel: viewModel)

                    RingoOSResizeHandle()
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .updating($resizeOffset) { value, state, _ in
                                    state = value.translation
                                }
                                .onEnded { value in
                                    contentSize.width = max(minWidth, contentSize.width + value.translation.width)
                                    contentSize.height = max(minHeight, contentSize.height + value.translation.height)
                                }
                        )
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                )
            }
            .frame(width: currentSize.width, height: isExpanded ? currentSize.height : nil)
            .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
            .offset(currentOffset)
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
            .transition(.opacity)
        }
    }
}
#endif
