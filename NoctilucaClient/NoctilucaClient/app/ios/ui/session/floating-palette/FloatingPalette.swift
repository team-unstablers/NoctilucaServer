//
//  FloatingPalette.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/21/26.
//

#if os(iOS)
import Foundation
import SwiftUI

enum FloatingPaletteAction: Equatable, Hashable {
    /// 줌 모드 / 터치 입력 모드를 전환한다
    case toggleZoomMode(ProjectionZoomMode)
    
    /// 소프트웨어 키보드를 표시한다.
    case softwareKeyboard
    
    @ViewBuilder
    var label: some View {
        switch self {
        case .softwareKeyboard:
            VStack {
                Image(systemName: "keyboard")
                    .font(.system(size: 18, weight: .medium))
            }
                .frame(width: 18, height: 18)
            Text(String(localized: "floating_palette.software_keyboard_toggle", defaultValue: "소프트웨어 키보드 토글"))
        case .toggleZoomMode(let zoomMode):
            VStack {
                Image(systemName: Self.zoomModeIcon(for: zoomMode))
                    .font(.system(size: 18, weight: .medium))
            }
                .frame(width: 18, height: 18)
            Text(Self.zoomModeLabel(for: zoomMode))
        }
    }

    private static func zoomModeIcon(for mode: ProjectionZoomMode) -> String {
        switch mode {
        case .cursorTracking:
            return "scope"
        case .free:
            return "hand.pinch"
        }
    }

    private static func zoomModeLabel(for mode: ProjectionZoomMode) -> String {
        switch mode {
        case .cursorTracking:
            return String(localized: "floating_palette.zoom_mode.cursor_tracking", defaultValue: "커서 추적 줌")
        case .free:
            return String(localized: "floating_palette.zoom_mode.free", defaultValue: "프리 줌")
        }
    }
}

struct FloatingPaletteMenu: View {
    var actions: [FloatingPaletteAction]
    var handler: ((FloatingPaletteAction) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(actions, id: \.self) { action in
                Button {
                    handler?(action)
                } label: {
                    HStack {
                        action.label
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct FloatingPaletteButton: View {

    var isPressing: Bool = false
    var isHovering: Bool = false

    private var currentOpacity: Double {
        if isPressing { return 1.0 }
        if isHovering { return 0.85 }
        return 0.35
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(.separator, lineWidth: 0.5)
                )
                .frame(width: 64, height: 64)
                .shadow(radius: isPressing ? 8 : 4, y: isPressing ? 4 : 2)

            Circle()
                .fill(.thickMaterial)
                .overlay(
                    Circle()
                        .strokeBorder(.separator, lineWidth: 0.5)
                )
                .frame(width: 40, height: 40)
                .shadow(radius: isPressing ? 6 : 3, y: isPressing ? 3 : 1.5)
        }
        .opacity(currentOpacity)
        .scaleEffect(isPressing ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isPressing)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
    }
}

struct FloatingPalette: View {
    var actions: [FloatingPaletteAction]
    var handler: ((FloatingPaletteAction) -> Void)?

    private let buttonSize: CGFloat = 72
    private let edgePadding: CGFloat = 8
    private let menuSpacing: CGFloat = 8
    private let tapThreshold: CGFloat = 5

    @State private var position: CGPoint = .zero
    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var isHovering = false
    @State private var hasAppeared = false
    @State private var shouldPresentMenu = false

    var body: some View {
        GeometryReader { geometry in
            let isOnLeft = position.x < geometry.size.width / 2

            if shouldPresentMenu {
                Color.black.opacity(0.001)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            shouldPresentMenu = false
                        }
                    }
            }

            FloatingPaletteButton(isPressing: isDragging, isHovering: isHovering)
                .overlay(alignment: .leading) {
                    if shouldPresentMenu && isOnLeft {
                        FloatingPaletteMenu(actions: actions) { action in
                            handler?(action)
                            
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                shouldPresentMenu = false
                            }
                        }
                            .fixedSize()
                            .offset(x: buttonSize + menuSpacing)
                            .transition(
                                .scale(scale: 0.5, anchor: .leading)
                                .combined(with: .opacity)
                            )
                    }
                }
                .overlay(alignment: .trailing) {
                    if shouldPresentMenu && !isOnLeft {
                        FloatingPaletteMenu(actions: actions) { action in
                            handler?(action)
                            
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                shouldPresentMenu = false
                            }
                        }
                            .fixedSize()
                            .offset(x: -(buttonSize + menuSpacing))
                            .transition(
                                .scale(scale: 0.5, anchor: .trailing)
                                .combined(with: .opacity)
                            )
                    }
                }
                .position(
                    x: position.x + dragOffset.width,
                    y: position.y + dragOffset.height
                )
                .onHover { hovering in
                    isHovering = hovering
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDragging = true
                            dragOffset = value.translation

                            let distance = hypot(value.translation.width, value.translation.height)
                            if distance > tapThreshold && shouldPresentMenu {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    shouldPresentMenu = false
                                }
                            }
                        }
                        .onEnded { value in
                            isDragging = false
                            let distance = hypot(value.translation.width, value.translation.height)

                            if distance < tapThreshold {
                                dragOffset = .zero
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    shouldPresentMenu.toggle()
                                }
                            } else {
                                let newPosition = CGPoint(
                                    x: position.x + value.translation.width,
                                    y: position.y + value.translation.height
                                )
                                dragOffset = .zero
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                                    position = snappedPosition(for: newPosition, in: geometry.size)
                                }
                            }
                        }
                )
                .onAppear {
                    guard !hasAppeared else { return }
                    hasAppeared = true
                    let halfButton = buttonSize / 2
                    position = CGPoint(
                        x: geometry.size.width - edgePadding - halfButton,
                        y: geometry.size.height / 2
                    )
                }
                .onChange(of: geometry.size) { _, newSize in
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                        position = snappedPosition(for: position, in: newSize)
                    }
                }
        }
    }

    private func snappedPosition(for point: CGPoint, in containerSize: CGSize) -> CGPoint {
        let halfButton = buttonSize / 2

        let snapLeft = edgePadding + halfButton
        let snapRight = containerSize.width - edgePadding - halfButton
        let snappedX = point.x < containerSize.width / 2 ? snapLeft : snapRight

        let minY = edgePadding + halfButton
        let maxY = containerSize.height - edgePadding - halfButton
        let snappedY = min(max(point.y, minY), maxY)

        return CGPoint(x: snappedX, y: snappedY)
    }
}

#Preview {
    VStack {
        FloatingPalette(actions: [.softwareKeyboard, .toggleZoomMode(.cursorTracking)]) { action in
            print("Selected action: \(action)")
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(.red)
}
#endif

