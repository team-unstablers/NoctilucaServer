//
//  ProjectionZoomController.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/21/26.
//

#if os(iOS)
import SwiftUI
import Combine

@MainActor
final class ProjectionZoomController: ObservableObject {
    // MARK: - Published State

    @Published private(set) var mode: ProjectionZoomMode = .off
    @Published var scale: CGFloat = 1.0
    @Published var offset: CGSize = .zero

    // MARK: - Internal Tracking

    private(set) var lastScale: CGFloat = 1.0
    private(set) var lastOffset: CGSize = .zero
    private(set) var trigger: CursorTrackingZoomTrigger?

    /// 키보드 자동진입 후 사용자가 수동으로 Free 모드로 전환했는지 추적
    private var didManuallyAdvanceFromKeyboardZoom: Bool = false

    /// 뷰에서 업데이트하는 geometry 정보 (클램핑 계산에 사용)
    private(set) var contentRect: CGRect = .zero
    private(set) var containerSize: CGSize = .zero

    // MARK: - Constants

    static let manualCursorTrackingScale: CGFloat = 1.5
    static let minScale: CGFloat = 1.0
    static let maxScale: CGFloat = 5.0
    static let deadzoneRatio: CGFloat = 0.30

    // MARK: - Geometry

    /// 뷰에서 geometry 변경 시 호출. 클램핑 계산에 사용됨.
    func updateGeometry(contentRect: CGRect, containerSize: CGSize) {
        self.contentRect = contentRect
        self.containerSize = containerSize
    }

    // MARK: - Mode Transitions

    /// 팔레트 버튼으로 모드 순환: OFF → 커서추적 → 프리 → OFF
    func cycleMode() {
        let nextMode = mode.next

        switch (mode, nextMode) {
        case (_, .off):
            // → OFF: 완전 리셋
            resetToOff()

        case (.off, .cursorTracking):
            // OFF → 커서추적 (수동)
            mode = .cursorTracking
            trigger = .manual
            didManuallyAdvanceFromKeyboardZoom = false
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                scale = Self.manualCursorTrackingScale
                offset = .zero
            }

        case (.cursorTracking, .free):
            // 커서추적 → 프리
            if trigger == .keyboard {
                didManuallyAdvanceFromKeyboardZoom = true
            }
            mode = .free

        default:
            mode = nextMode
        }
    }

    /// 키보드 등장 시 자동 진입
    func enterKeyboardZoom(visibleRatio: CGFloat) {
        guard mode == .off else { return }

        /*
        let clampedRatio = max(0.1, min(1.0, visibleRatio))
        let autoScale = min(1.0 / clampedRatio, Self.maxScale)
         */

        mode = .cursorTracking
        trigger = .keyboard
        didManuallyAdvanceFromKeyboardZoom = false

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            scale = visibleRatio // max(autoScale, Self.minScale)
            offset = .zero
        }
    }

    /// 키보드 dismiss 시 처리
    func handleKeyboardDismissed() {
        guard trigger == .keyboard else { return }

        if didManuallyAdvanceFromKeyboardZoom {
            // 사용자가 수동으로 프리 줌으로 전환했으면 유지
            trigger = nil
            didManuallyAdvanceFromKeyboardZoom = false
            return
        }

        // 키보드로 자동진입했으면 자동 해제
        resetToOff()
    }

    /// 더블 탭으로 리셋 (모드는 유지, scale/offset만 초기화)
    func resetZoomLevel() {
        lastScale = 1.0
        lastOffset = .zero
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            scale = 1.0
            offset = .zero
        }
    }

    // MARK: - Pinch Gesture Handling

    func handlePinchChanged(magnification: CGFloat) {
        let newScale = lastScale * magnification
        scale = min(max(newScale, Self.minScale), Self.maxScale)
        // scale 변경에 따라 offset 재클램핑 (빈 공간 방지)
        autoClampOffset()
    }

    func handlePinchEnded() {
        lastScale = scale
        if scale <= Self.minScale {
            resetZoomLevel()
        } else {
            autoClampOffset()
            lastOffset = offset
        }
    }

    // MARK: - Free Zoom Drag Handling

    func handleFreeDragChanged(translation: CGSize) {
        guard mode == .free else { return }
        let raw = CGSize(
            width: lastOffset.width + translation.width,
            height: lastOffset.height + translation.height
        )
        offset = clampedOffset(raw, contentRect: contentRect, containerSize: containerSize)
    }

    func handleFreeDragEnded() {
        lastOffset = offset
    }

    // MARK: - Cursor Tracking

    /// 뷰포트를 커서 위치 중심으로 즉시 이동한다. 모드 진입 직후 호출용.
    func centerViewportOnCursor(normalizedCursorPosition: CGPoint) {
        guard mode == .cursorTracking, scale > 1.0 else { return }

        // 커서가 뷰포트 중앙에 오도록 offset 계산
        let cursorInContent = CGPoint(
            x: contentRect.origin.x + normalizedCursorPosition.x * contentRect.width,
            y: contentRect.origin.y + normalizedCursorPosition.y * contentRect.height
        )
        let containerCenter = CGPoint(
            x: containerSize.width / 2,
            y: containerSize.height / 2
        )
        let rawOffset = CGSize(
            width: containerCenter.x - cursorInContent.x,
            height: containerCenter.y - cursorInContent.y
        )
        let clamped = clampedOffset(rawOffset, contentRect: contentRect, containerSize: containerSize)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            offset = clamped
            lastOffset = clamped
        }
    }

    /// 커서 위치가 변경될 때 뷰포트를 조정한다.
    /// - Parameters:
    ///   - normalizedCursorPosition: 0~1 범위의 서버 커서 위치
    ///   - contentRect: fittedProjectionRect 결과 (포인트 단위)
    ///   - containerSize: GeometryReader 크기
    func updateViewportForCursor(
        normalizedCursorPosition: CGPoint,
        contentRect: CGRect,
        containerSize: CGSize
    ) {
        guard mode == .cursorTracking, scale > 1.0 else { return }

        // 1) 커서의 content rect 내 위치 (포인트 단위)
        let cursorInContent = CGPoint(
            x: contentRect.origin.x + normalizedCursorPosition.x * contentRect.width,
            y: contentRect.origin.y + normalizedCursorPosition.y * contentRect.height
        )

        // 2) 현재 보이는 영역 계산 (scaleEffect center anchor 기준)
        // offset은 pre-scale 좌표이므로 화면상 이동량 = offset * scale
        // 가시 영역의 중심은 화면 중심에서 offset만큼 반대로 이동
        let visibleWidth = containerSize.width / scale
        let visibleHeight = containerSize.height / scale
        let visibleCenterX = containerSize.width / 2 - offset.width
        let visibleCenterY = containerSize.height / 2 - offset.height
        let visibleRect = CGRect(
            x: visibleCenterX - visibleWidth / 2,
            y: visibleCenterY - visibleHeight / 2,
            width: visibleWidth,
            height: visibleHeight
        )

        // 3) Deadzone: 가시 영역 가장자리 30%
        let marginX = visibleWidth * Self.deadzoneRatio
        let marginY = visibleHeight * Self.deadzoneRatio
        let safeRect = visibleRect.insetBy(dx: marginX, dy: marginY)

        // 4) 커서가 safe rect 밖에 있으면 offset 조정
        var newOffset = offset
        if cursorInContent.x < safeRect.minX {
            newOffset.width += (safeRect.minX - cursorInContent.x)
        } else if cursorInContent.x > safeRect.maxX {
            newOffset.width -= (cursorInContent.x - safeRect.maxX)
        }
        if cursorInContent.y < safeRect.minY {
            newOffset.height += (safeRect.minY - cursorInContent.y)
        } else if cursorInContent.y > safeRect.maxY {
            newOffset.height -= (cursorInContent.y - safeRect.maxY)
        }

        // 5) Clamp & animate
        let clamped = clampedOffset(newOffset, contentRect: contentRect, containerSize: containerSize)
        if clamped != offset {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.offset = clamped
                self.lastOffset = clamped
            }
        }
    }

    // MARK: - Offset Clamping

    /// 콘텐츠가 뷰포트 밖으로 벗어나지 않도록 offset을 클램핑한다.
    func clampOffset(contentRect: CGRect, containerSize: CGSize) {
        let clamped = clampedOffset(offset, contentRect: contentRect, containerSize: containerSize)
        if clamped != offset {
            offset = clamped
            lastOffset = clamped
        }
    }

    private func clampedOffset(
        _ offset: CGSize,
        contentRect: CGRect,
        containerSize: CGSize
    ) -> CGSize {
        guard scale > 1.0 else {
            return .zero
        }

        // .offset()은 .scaleEffect() 안쪽에 적용되므로,
        // 화면상 실제 이동량 = offset * scale 이다.
        // 따라서 최대 offset = 최대 화면 이동량 / scale.
        let scaledContentWidth = contentRect.width * scale
        let scaledContentHeight = contentRect.height * scale
        let maxOffsetX = max(0, (scaledContentWidth - containerSize.width) / (2 * scale))
        let maxOffsetY = max(0, (scaledContentHeight - containerSize.height) / (2 * scale))

        return CGSize(
            width: min(max(offset.width, -maxOffsetX), maxOffsetX),
            height: min(max(offset.height, -maxOffsetY), maxOffsetY)
        )
    }

    // MARK: - Private Helpers

    private func autoClampOffset() {
        let clamped = clampedOffset(offset, contentRect: contentRect, containerSize: containerSize)
        if clamped != offset {
            offset = clamped
        }
    }

    private func resetToOff() {
        mode = .off
        trigger = nil
        didManuallyAdvanceFromKeyboardZoom = false
        lastScale = 1.0
        lastOffset = .zero
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            scale = 1.0
            offset = .zero
        }
    }
}
#endif
