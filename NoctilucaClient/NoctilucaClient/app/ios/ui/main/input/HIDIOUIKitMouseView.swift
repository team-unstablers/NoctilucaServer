//
//  HIDIOUIKitMouseView.swift
//  NoctilucaClient
//
//  Created by Codex on 1/29/26.
//

#if os(iOS)
import SwiftUI
import UIKit

import SiriusKitClient

struct HIDIOUIKitMouseView: View {
    let mouse: HIDIOUIKitMouse

    @Binding var mode: AppSettings.TouchInputMode
    @Binding var trackpadMoveMultiplier: Double

    var zoomMode: ProjectionZoomMode = .free
    var contentRect: CGRect = .zero
    var zoomScale: CGFloat = 1.0
    var zoomOffset: CGSize = .zero
    var onPinchChanged: ((CGFloat) -> Void)?
    var onPinchEnded: (() -> Void)?
    var onFreeDragChanged: ((CGSize) -> Void)?
    var onFreeDragEnded: (() -> Void)?

    var body: some View {
        HIDIOUIKitMouseCaptureView(
            pointer: mouse,
            mode: $mode,
            trackpadMoveMultiplier: $trackpadMoveMultiplier,
            zoomMode: zoomMode,
            contentRect: contentRect,
            zoomScale: zoomScale,
            zoomOffset: zoomOffset,
            onPinchChanged: onPinchChanged,
            onPinchEnded: onPinchEnded,
            onFreeDragChanged: onFreeDragChanged,
            onFreeDragEnded: onFreeDragEnded
        )
    }
}

private struct HIDIOUIKitMouseCaptureView: UIViewRepresentable {
    let pointer: HIDIOUIKitMouse

    @Binding var mode: AppSettings.TouchInputMode
    @Binding var trackpadMoveMultiplier: Double

    var zoomMode: ProjectionZoomMode = .free
    var contentRect: CGRect = .zero
    var zoomScale: CGFloat = 1.0
    var zoomOffset: CGSize = .zero
    var onPinchChanged: ((CGFloat) -> Void)?
    var onPinchEnded: (() -> Void)?
    var onFreeDragChanged: ((CGSize) -> Void)?
    var onFreeDragEnded: (() -> Void)?

    func makeUIView(context: Context) -> MouseInputCaptureView {
        let view = MouseInputCaptureView(pointer: pointer)
        view.updateInputMode(mode, trackpadMoveMultiplier: trackpadMoveMultiplier)
        view.updateZoomMode(zoomMode)
        view.updateContentRect(contentRect, zoomScale: zoomScale, zoomOffset: zoomOffset)
        view.onPinchChanged = onPinchChanged
        view.onPinchEnded = onPinchEnded
        view.onFreeDragChanged = onFreeDragChanged
        view.onFreeDragEnded = onFreeDragEnded
        return view
    }

    func updateUIView(_ uiView: MouseInputCaptureView, context: Context) {
        uiView.updateInputMode(mode, trackpadMoveMultiplier: trackpadMoveMultiplier)
        uiView.updateZoomMode(zoomMode)
        uiView.updateContentRect(contentRect, zoomScale: zoomScale, zoomOffset: zoomOffset)
        uiView.onPinchChanged = onPinchChanged
        uiView.onPinchEnded = onPinchEnded
        uiView.onFreeDragChanged = onFreeDragChanged
        uiView.onFreeDragEnded = onFreeDragEnded
    }

    static func dismantleUIView(_ uiView: MouseInputCaptureView, coordinator: ()) {
        uiView.teardown()
    }
}

/// CADisplayLink의 target strong retain으로 인한 retain cycle을 방지하기 위한 프록시.
private final class DisplayLinkProxy {
    var handler: ((CADisplayLink) -> Void)?

    init(handler: @escaping (CADisplayLink) -> Void) {
        self.handler = handler
    }

    @objc func tick(_ link: CADisplayLink) {
        handler?(link)
    }
}

/// 두 손가락 스크롤 중의 미세한 finger span 변화로 핀치가 너무 쉽게 시작되는 것을 막는다.
private final class ThresholdPinchGestureRecognizer: UIGestureRecognizer {
    var activationScaleThreshold: CGFloat = 0.03
    var minimumSpanDelta: CGFloat = 0

    private var firstTouch: UITouch?
    private var secondTouch: UITouch?
    private var baselineDistance: CGFloat = 0
    private var activationDistance: CGFloat = 0

    private(set) var scale: CGFloat = 1.0

    override func reset() {
        super.reset()
        firstTouch = nil
        secondTouch = nil
        baselineDistance = 0
        activationDistance = 0
        scale = 1.0
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let view else {
            state = .failed
            return
        }

        for touch in touches {
            if firstTouch == nil {
                firstTouch = touch
            } else if secondTouch == nil, touch != firstTouch {
                secondTouch = touch
            } else if touch != firstTouch, touch != secondTouch {
                state = state == .possible ? .failed : .cancelled
                return
            }
        }

        guard let firstTouch, let secondTouch else {
            return
        }

        let distance = distance(between: firstTouch, and: secondTouch, in: view)
        baselineDistance = distance
        activationDistance = distance
        scale = 1.0
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let view,
              let firstTouch,
              let secondTouch
        else {
            state = .failed
            return
        }

        guard touches.contains(firstTouch) || touches.contains(secondTouch) else {
            return
        }

        let currentDistance = distance(between: firstTouch, and: secondTouch, in: view)
        guard currentDistance > 0 else {
            return
        }

        if state == .possible {
            guard baselineDistance > 0 else {
                baselineDistance = currentDistance
                activationDistance = currentDistance
                return
            }

            let totalScaleDelta = abs((currentDistance / baselineDistance) - 1.0)
            let spanDelta = abs(currentDistance - baselineDistance)
            guard totalScaleDelta >= activationScaleThreshold,
                  spanDelta >= minimumSpanDelta
            else {
                return
            }

            activationDistance = currentDistance
            scale = 1.0
            state = .began
            return
        }

        guard activationDistance > 0 else {
            activationDistance = currentDistance
            scale = 1.0
            state = .changed
            return
        }

        scale = currentDistance / activationDistance
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let firstTouch, let secondTouch else {
            state = .failed
            return
        }

        guard touches.contains(firstTouch) || touches.contains(secondTouch) else {
            return
        }

        if state == .began || state == .changed {
            state = .ended
        } else {
            state = .failed
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }

    private func distance(between firstTouch: UITouch, and secondTouch: UITouch, in view: UIView) -> CGFloat {
        let firstLocation = firstTouch.location(in: view)
        let secondLocation = secondTouch.location(in: view)
        return hypot(secondLocation.x - firstLocation.x, secondLocation.y - firstLocation.y)
    }
}

private final class MouseInputCaptureView: UIView, UIGestureRecognizerDelegate {
    private static let trackpadPinchActivationScaleThreshold: CGFloat = 0.14
    private static let trackpadPinchMinimumSpanDelta: CGFloat = 18.0
    private static let touchPinchActivationScaleThreshold: CGFloat = 0.03
    private static let touchPinchMinimumSpanDelta: CGFloat = 0

    private let pointer: HIDIOUIKitMouse
    private var inputMode: AppSettings.TouchInputMode = .touch
    private var trackpadMoveMultiplier: CGFloat = 1.0

    private let tapRecognizer = UITapGestureRecognizer()
    private let twoFingerTapRecognizer = UITapGestureRecognizer()
    private let panRecognizer = UIPanGestureRecognizer()
    private let twoFingerPanRecognizer = UIPanGestureRecognizer()
    private let chordedDragRecognizer = ChordedDragGestureRecognizer()
    private let threeFingerPanRecognizer = UIPanGestureRecognizer()

    private let mouseMoveRecognizer        = UIHoverGestureRecognizer()
    private let mouseLeftClickRecognizer   = UITapGestureRecognizer()
    private let mouseRightClickRecognizer  = UITapGestureRecognizer()
    private let mouseCenterClickRecognizer = UITapGestureRecognizer()
    private let mouseScrollRecognizer      = UIPanGestureRecognizer()

    // Zoom gesture recognizers
    private let pinchRecognizer = ThresholdPinchGestureRecognizer()

    private var isChordedDragging: Bool = false
    private var isScrolling: Bool = false

    // Content rect & zoom state for coordinate mapping
    private var contentRect: CGRect = .zero
    private var zoomScale: CGFloat = 1.0
    private var zoomOffset: CGSize = .zero

    // Zoom mode
    private(set) var zoomMode: ProjectionZoomMode = .free
    var onPinchChanged: ((CGFloat) -> Void)?
    var onPinchEnded: (() -> Void)?
    var onFreeDragChanged: ((CGSize) -> Void)?
    var onFreeDragEnded: (() -> Void)?

    // Unified Inertia Engine
    private var inertiaDisplayLink: CADisplayLink?
    private var inertiaDisplayLinkProxy: DisplayLinkProxy?
    private var inertiaLastTimestamp: CFTimeInterval?

    private var moveInertiaVelocity: CGPoint = .zero
    private var scrollInertiaVelocity: CGPoint = .zero

    init(pointer: HIDIOUIKitMouse) {
        self.pointer = pointer
        super.init(frame: .zero)
        backgroundColor = .clear
        isOpaque = false
        isMultipleTouchEnabled = true
        setupRecognizers()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    deinit {
        teardown()
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)

        if newWindow == nil {
            teardown()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // geometry는 contentRect.size를 사용 (updateContentRect에서 설정)
        // layoutSubviews는 bounds 변경 시 호출되지만, 좌표 정규화는 contentRect 기준이므로
        // bounds.size가 아닌 contentRect.size가 올바른 geometry이다.
        if contentRect.width > 0, contentRect.height > 0 {
            pointer.updateGeometry(contentRect.size)
        }
    }

    func updateInputMode(_ mode: AppSettings.TouchInputMode, trackpadMoveMultiplier: Double) {
        inputMode = mode
        self.trackpadMoveMultiplier = max(0.1, CGFloat(trackpadMoveMultiplier))
        switch mode {
        case .touch:
            pinchRecognizer.activationScaleThreshold = Self.touchPinchActivationScaleThreshold
            pinchRecognizer.minimumSpanDelta = Self.touchPinchMinimumSpanDelta
        case .trackpad:
            pinchRecognizer.activationScaleThreshold = Self.trackpadPinchActivationScaleThreshold
            pinchRecognizer.minimumSpanDelta = Self.trackpadPinchMinimumSpanDelta
        }
        if mode != .trackpad {
            moveInertiaVelocity = .zero
        }
        scrollInertiaVelocity = .zero
        checkInertiaState()
        // No explicit configureRecognizerState() needed as delegate handles it dynamically.
    }

    func updateZoomMode(_ mode: ProjectionZoomMode) {
        zoomMode = mode
    }

    func updateContentRect(_ rect: CGRect, zoomScale: CGFloat, zoomOffset: CGSize) {
        contentRect = rect
        self.zoomScale = zoomScale
        self.zoomOffset = zoomOffset
        pointer.updateGeometry(rect.size)
    }

    func teardown() {
        stopInertiaLoop()

        onPinchChanged = nil
        onPinchEnded = nil
        onFreeDragChanged = nil
        onFreeDragEnded = nil
    }

    /// 화면 터치 좌표 → 콘텐츠 로컬 좌표 변환 (줌 역변환 + 선택적 클램핑)
    ///
    /// video view의 변환 체인:
    ///   .offset(zoomOffset) → .frame(rect) → .position(rect.mid) → .scaleEffect(zoomScale)
    /// 역변환:
    ///   contentLocal = (screenPoint - rect.mid) / scale + rect.size/2 - zoomOffset
    ///
    /// - Parameter clamp: contentRect 범위로 클램프할지 여부. 하드웨어 마우스 드래그 등
    ///   인접 디스플레이로의 cross-display 라우팅이 필요한 경로에서는 `false`로 호출한다.
    private func locationInContentRect(_ screenPoint: CGPoint, clamp: Bool = true) -> CGPoint {
        let cx = (screenPoint.x - contentRect.midX) / zoomScale + contentRect.width / 2 - zoomOffset.width
        let cy = (screenPoint.y - contentRect.midY) / zoomScale + contentRect.height / 2 - zoomOffset.height
        if clamp {
            return CGPoint(
                x: min(max(cx, 0), contentRect.width),
                y: min(max(cy, 0), contentRect.height)
            )
        }
        return CGPoint(x: cx, y: cy)
    }

    private func setupRecognizers() {
        tapRecognizer.numberOfTouchesRequired = 1
        tapRecognizer.addTarget(self, action: #selector(handleTap(_:)))

        twoFingerTapRecognizer.numberOfTouchesRequired = 2
        twoFingerTapRecognizer.addTarget(self, action: #selector(handleTwoFingerTap(_:)))

        panRecognizer.minimumNumberOfTouches = 1
        panRecognizer.maximumNumberOfTouches = 1
        panRecognizer.addTarget(self, action: #selector(handlePan(_:)))

        twoFingerPanRecognizer.minimumNumberOfTouches = 2
        twoFingerPanRecognizer.maximumNumberOfTouches = 2
        twoFingerPanRecognizer.addTarget(self, action: #selector(handleTwoFingerPan(_:)))
        
        threeFingerPanRecognizer.minimumNumberOfTouches = 3
        threeFingerPanRecognizer.maximumNumberOfTouches = 3
        threeFingerPanRecognizer.addTarget(self, action: #selector(handleThreeFingerPan(_:)))

        chordedDragRecognizer.maximumFirstTouchMovement = 8
        chordedDragRecognizer.minimumFirstTouchHoldDuration = 0.08
        chordedDragRecognizer.addTarget(self, action: #selector(handleChordedDrag(_:)))

        tapRecognizer.require(toFail: twoFingerTapRecognizer)
        // panRecognizer.require(toFail: chordedDragRecognizer) // Removed to allow sequential chorded drag

        tapRecognizer.delegate = self
        twoFingerTapRecognizer.delegate = self
        panRecognizer.delegate = self
        twoFingerPanRecognizer.delegate = self
        chordedDragRecognizer.delegate = self
        
        // All recognizers are enabled by default; delegate controls participation.
        addGestureRecognizer(twoFingerTapRecognizer)
        addGestureRecognizer(tapRecognizer)
        addGestureRecognizer(twoFingerPanRecognizer)
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(chordedDragRecognizer)
        addGestureRecognizer(threeFingerPanRecognizer)
        
        mouseMoveRecognizer.addTarget(self, action: #selector(handleMouseMove(_:)))

        mouseLeftClickRecognizer.numberOfTouchesRequired = 1
        mouseLeftClickRecognizer.buttonMaskRequired = .primary
        mouseLeftClickRecognizer.delegate = self
        mouseLeftClickRecognizer.addTarget(self, action: #selector(handleMouseClick(_:)))

        mouseRightClickRecognizer.numberOfTouchesRequired = 1
        mouseRightClickRecognizer.buttonMaskRequired = .secondary
        mouseRightClickRecognizer.delegate = self
        mouseRightClickRecognizer.addTarget(self, action: #selector(handleMouseClick(_:)))
        
        /*
         // 중앙 버튼은 인식이 불가능하더라구요. ㅠ
        mouseCenterClickRecognizer.numberOfTouchesRequired = 1
        mouseCenterClickRecognizer.buttonMaskRequired = .init(rawValue: 3)
        mouseCenterClickRecognizer.addTarget(self, action: #selector(handleMouseClick(_:)))
        mouseCenterClickRecognizer.delegate = self
         */

        mouseScrollRecognizer.minimumNumberOfTouches = 1
        mouseScrollRecognizer.maximumNumberOfTouches = 1
        mouseScrollRecognizer.allowedScrollTypesMask = [.discrete]
        mouseScrollRecognizer.allowedTouchTypes = []
        mouseScrollRecognizer.addTarget(self, action: #selector(handleMouseScroll(_:)))
        
        addGestureRecognizer(mouseMoveRecognizer)
        addGestureRecognizer(mouseLeftClickRecognizer)
        addGestureRecognizer(mouseRightClickRecognizer)
        addGestureRecognizer(mouseScrollRecognizer)

        // Zoom gesture recognizers
        pinchRecognizer.delegate = self
        pinchRecognizer.addTarget(self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinchRecognizer)
    }

    // MARK: - Touch Handling (Direct)
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Cancel any active inertia as soon as a finger touches the screen
        stopMoveInertia()
        stopScrollInertia()

        guard let touch = touches.first else {
            super.touchesBegan(touches, with: event)
            return
        }

        // Hardware mouse: handle regardless of input mode or zoom mode
        if touch.type == .indirectPointer {
            let location = locationInContentRect(touch.location(in: self), clamp: false)
            pointer.moveAbsolute(to: location)

            if touch.gestureRecognizers?.contains(mouseRightClickRecognizer) == true {
                pointer.buttonDown(.right)
            } else {
                pointer.buttonDown(.left)
            }
            return
        }

        /*
        // Free zoom + trackpad: block direct touch mouse input
        // Free zoom + touch: allow direct touch (커서 이동 + 클릭)
        guard !(zoomMode == .free && inputMode != .touch) else {
            super.touchesBegan(touches, with: event)
            return
        }
         */

        // Direct touch: only in touch mode
        guard inputMode == .touch,
              event?.allTouches?.count == 1
        else {
            super.touchesBegan(touches, with: event)
            return
        }

        let location = locationInContentRect(touch.location(in: self))
        pointer.moveAbsolute(to: location)
        pointer.buttonDown(.left)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            super.touchesMoved(touches, with: event)
            return
        }

        if touch.type == .indirectPointer {
            let location = locationInContentRect(touch.location(in: self), clamp: false)
            pointer.moveAbsolute(to: location)
            return
        }

        /*
        guard zoomMode != .free else {
            super.touchesMoved(touches, with: event)
            return
        }
         */

        guard inputMode == .touch,
              event?.allTouches?.count == 1
        else {
            
            if event?.allTouches?.count != 1 {
                // reset button state on multi-touch to prevent stuck buttons
                pointer.buttonUp(.left)
            }
            
            super.touchesMoved(touches, with: event)
            return
        }

        let location = locationInContentRect(touch.location(in: self))
        pointer.moveAbsolute(to: location)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            super.touchesEnded(touches, with: event)
            return
        }

        if touch.type == .indirectPointer {
            let location = locationInContentRect(touch.location(in: self), clamp: false)
            pointer.moveAbsolute(to: location)

            if touch.gestureRecognizers?.contains(mouseRightClickRecognizer) == true {
                pointer.buttonUp(.right)
            } else {
                pointer.buttonUp(.left)
            }
            return
        }

        /*
        guard zoomMode != .free else {
            super.touchesEnded(touches, with: event)
            return
        }
         */

        guard inputMode == .touch,
              event?.allTouches?.count == 1
        else {
            super.touchesEnded(touches, with: event)
            return
        }

        let location = locationInContentRect(touch.location(in: self))
        pointer.moveAbsolute(to: location)
        pointer.buttonUp(.left)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else {
            super.touchesCancelled(touches, with: event)
            return
        }

        if touch.type == .indirectPointer {
            let location = locationInContentRect(touch.location(in: self), clamp: false)
            pointer.moveAbsolute(to: location)

            if touch.gestureRecognizers?.contains(mouseRightClickRecognizer) == true {
                pointer.buttonUp(.right)
            } else {
                pointer.buttonUp(.left)
            }
            return
        }

        guard zoomMode != .free else {
            super.touchesCancelled(touches, with: event)
            return
        }

        guard inputMode == .touch else {
            super.touchesCancelled(touches, with: event)
            return
        }

        let location = locationInContentRect(touch.location(in: self))
        pointer.moveAbsolute(to: location)
        pointer.buttonUp(.left)
    }

    // MARK: - UIGestureRecognizerDelegate
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if touch.type == .indirectPointer {
            // Hardware mouse touches are handled directly in touches* methods,
            // so block touch-mode and zoom gesture recognizers from receiving them.
            if gestureRecognizer == tapRecognizer ||
               gestureRecognizer == twoFingerTapRecognizer ||
               gestureRecognizer == panRecognizer ||
               gestureRecognizer == twoFingerPanRecognizer ||
               gestureRecognizer == chordedDragRecognizer ||
               gestureRecognizer == pinchRecognizer {
                return false
            }
        } else {
            // Block mouse recognizers from receiving finger touches
            // to prevent them from stealing taps from tapRecognizer.
            if gestureRecognizer == mouseLeftClickRecognizer ||
               gestureRecognizer == mouseRightClickRecognizer {
                return false
            }
        }
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return false
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Zoom gesture recognizers
        /*
        // Free zoom mode
        if zoomMode == .free {
            // 터치 모드: 모든 터치 제스처 허용 (커서 이동, 클릭, 우클릭 등)
            // → 이 경우 아래의 input mode 정책으로 넘어감
            if inputMode != .touch {
                // 트랙패드 모드: twoFingerPan만 허용 (줌 패닝), 나머지 블록
                if gestureRecognizer == twoFingerPanRecognizer {
                    return true
                }
                if gestureRecognizer == tapRecognizer ||
                   gestureRecognizer == twoFingerTapRecognizer ||
                   gestureRecognizer == panRecognizer ||
                   gestureRecognizer == chordedDragRecognizer {
                    return false
                }
            }
        }
         */

        // Enforce input mode policies at the start of gestures
        switch inputMode {
        case .touch:
            // In Touch mode, single finger pan/tap is handled directly by touchesBegan/Moved/Ended
            if gestureRecognizer == tapRecognizer ||
               gestureRecognizer == chordedDragRecognizer ||
               gestureRecognizer == panRecognizer { // Disable PanRecognizer for single touch
                return false
            }
        case .trackpad:
            break
        }
        return true
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }

        // 프리 줌 + 터치 모드: 탭 위치로 클릭
        if zoomMode == .free, inputMode == .touch {
            let location = locationInContentRect(recognizer.location(in: self))
            pointer.moveAbsolute(to: location)
            pointer.buttonDown(.left)
            pointer.buttonUp(.left)
            return
        }

        switch inputMode {
        case .touch:
            // Should be handled by touchesBegan/Moved/Ended
            break
        case .trackpad:
            pointer.buttonDown(.left)
            pointer.buttonUp(.left)
        }
    }

    @objc private func handleTwoFingerTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }

        switch inputMode {
        case .touch:
            let location = locationInContentRect(averageLocation(for: recognizer))
            pointer.moveAbsolute(to: location)
            pointer.buttonDown(.right)
            pointer.buttonUp(.right)
        case .trackpad:
            pointer.buttonDown(.right)
            pointer.buttonUp(.right)
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        if isChordedDragging {
            return
        }

        switch inputMode {
        case .touch:
            // Handled by touchesBegan/Moved/Ended
            break
        case .trackpad:
            handleTrackpadMove(recognizer)
        }
    }

    private func handleTouchDrag(_ recognizer: UIPanGestureRecognizer) {
        // Deprecated: Handled by direct touches overrides
    }

    private func handleTrackpadMove(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        switch recognizer.state {
        case .began:
            stopMoveInertia()
            recognizer.setTranslation(.zero, in: self)
        case .changed:
            // With setTranslation(.zero) called after reading, 'translation' is the delta since last change.
            let delta = translation
            recognizer.setTranslation(.zero, in: self)
            pointer.moveRelativePercentage(by: scaledDelta(delta))
        case .ended, .cancelled, .failed:
            let velocity = recognizer.velocity(in: self)
            startMoveInertia(with: velocity)
        default:
            break
        }
    }

    @objc private func handleTwoFingerPan(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)

        switch recognizer.state {
        case .began:
            // Prevent scroll if we are already dragging
            if isChordedDragging {
                return
            }
            isScrolling = true
            stopScrollInertia()
            recognizer.setTranslation(.zero, in: self)
        case .changed:
            guard isScrolling else { return }
            // Y is inverted for scroll naturally
            let delta = CGPoint(x: translation.x, y: -translation.y)
            recognizer.setTranslation(.zero, in: self)
            pointer.scroll(delta: normalizedScrollDelta(delta))
        case .ended, .cancelled, .failed:
            if isScrolling {
                isScrolling = false
                let velocity = recognizer.velocity(in: self)
                startScrollInertia(with: velocity)
            }
        default:
            break
        }
    }
    
    @objc private func handleThreeFingerPan(_ recognizer: UIPanGestureRecognizer) {
        if zoomMode == .free {
            let translation = recognizer.translation(in: self)
            switch recognizer.state {
            case .began, .changed:
                onFreeDragChanged?(CGSize(width: translation.x, height: translation.y))
            case .ended, .cancelled, .failed:
                onFreeDragEnded?()
            default:
                break
            }
            return
        }
    }
    
    @objc private func handleMouseMove(_ recognizer: UIHoverGestureRecognizer) {
        switch recognizer.state {
        case .changed:
            let location = locationInContentRect(recognizer.location(in: self))
            pointer.moveAbsolute(to: location)
        default:
            break
        }
    }
    
    @objc private func handleMouseClick(_ recognizer: UITapGestureRecognizer) {
        return
        /*
        let button: MouseButtonType = if recognizer == mouseLeftClickRecognizer {
            .left
        } else if recognizer == mouseRightClickRecognizer {
            .right
        } else if recognizer == mouseCenterClickRecognizer {
            .middle
        } else {
            .left
        }
        
        if button == .left {
            // UIKit 터치 핸들러에서 처리해줄 거임 (여기서 하면 드래그 안됨 ㅜ)
            return
        }
        
        let location = recognizer.location(in: self)

        switch recognizer.state {
        case .ended:
            pointer.moveAbsolute(to: location)
            pointer.buttonDown(button)
            pointer.buttonUp(button)
            
        default:
            break
        }
         */
    }
    
    @objc private func handleMouseScroll(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)

        switch recognizer.state {
        case .began:
            // Prevent scroll if we are already dragging
            if isChordedDragging {
                return
            }
            isScrolling = true
            stopScrollInertia()
            recognizer.setTranslation(.zero, in: self)
        case .changed:
            guard isScrolling else { return }
            // Y is inverted for scroll naturally
            let delta = CGPoint(x: translation.x, y: -translation.y)
            recognizer.setTranslation(.zero, in: self)
            pointer.scroll(delta: normalizedScrollDelta(delta))
        case .ended, .cancelled, .failed:
            if isScrolling {
                isScrolling = false
            }
        default:
            break
        }
    }

    @objc private func handleChordedDrag(_ recognizer: ChordedDragGestureRecognizer) {
        guard inputMode == .trackpad else {
            return
        }

        switch recognizer.state {
        case .began:
            // Prevent drag if we are scrolling
            if isScrolling {
                return
            }
            isChordedDragging = true
            stopMoveInertia()
            stopScrollInertia()
            pointer.buttonDown(.left)
        case .changed:
            guard isChordedDragging else { return }
            let delta = CGPoint(x: recognizer.translation.x, y: recognizer.translation.y)
            pointer.moveRelativePercentage(by: scaledDelta(delta))
        case .ended, .cancelled, .failed:
            if isChordedDragging {
                isChordedDragging = false
                pointer.buttonUp(.left)
            }
        default:
            break
        }
    }

    // MARK: - Zoom Gesture Handlers

    @objc private func handlePinch(_ recognizer: UIGestureRecognizer) {
        guard let recognizer = recognizer as? ThresholdPinchGestureRecognizer else {
            return
        }

        switch recognizer.state {
        case .began, .changed:
            onPinchChanged?(recognizer.scale)
        case .ended, .cancelled, .failed:
            onPinchEnded?()
        default:
            break
        }
    }

    // MARK: - Helpers

    private func averageLocation(for recognizer: UIGestureRecognizer) -> CGPoint {
        let count = recognizer.numberOfTouches
        guard count > 0 else {
            return recognizer.location(in: self)
        }

        var totalX: CGFloat = 0
        var totalY: CGFloat = 0

        for index in 0..<count {
            let location = recognizer.location(ofTouch: index, in: self)
            totalX += location.x
            totalY += location.y
        }

        return CGPoint(x: totalX / CGFloat(count), y: totalY / CGFloat(count))
    }

    private func startMoveInertia(with velocity: CGPoint) {
        guard inputMode == .trackpad else { return }
        let speed = hypot(velocity.x, velocity.y)
        guard speed >= 40.0 else { return }

        moveInertiaVelocity = velocity
        ensureInertiaLoop()
    }

    private func stopMoveInertia() {
        moveInertiaVelocity = .zero
        checkInertiaState()
    }
    
    private func startScrollInertia(with velocity: CGPoint) {
        let speed = hypot(velocity.x, velocity.y)
        guard speed >= 50.0 else { return }

        scrollInertiaVelocity = velocity
        ensureInertiaLoop()
    }

    private func stopScrollInertia() {
        scrollInertiaVelocity = .zero
        checkInertiaState()
    }

    private func ensureInertiaLoop() {
        if inertiaDisplayLink == nil {
            inertiaLastTimestamp = nil
            let proxy = DisplayLinkProxy { [weak self] link in
                self?.handleInertiaTick(link)
            }
            inertiaDisplayLinkProxy = proxy
            let link = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.tick(_:)))
            link.add(to: .main, forMode: .common)
            inertiaDisplayLink = link
        }
        inertiaDisplayLink?.isPaused = false
    }

    private func stopInertiaLoop() {
        inertiaDisplayLink?.invalidate()
        inertiaDisplayLink = nil
        inertiaDisplayLinkProxy = nil
        inertiaLastTimestamp = nil
        moveInertiaVelocity = .zero
        scrollInertiaVelocity = .zero
    }
    
    private func checkInertiaState() {
        if moveInertiaVelocity == .zero && scrollInertiaVelocity == .zero {
            inertiaDisplayLink?.isPaused = true
            inertiaLastTimestamp = nil
        }
    }

    private func handleInertiaTick(_ link: CADisplayLink) {
        let now = link.timestamp
        let last = inertiaLastTimestamp ?? now
        let dt = max(0.0, now - last)
        inertiaLastTimestamp = now
        
        // 1. Move Inertia
        if moveInertiaVelocity != .zero {
            if inputMode != .trackpad {
                moveInertiaVelocity = .zero
            } else {
                let decelerationRate: CGFloat = 0.95
                let decay = pow(decelerationRate, CGFloat(dt) * 60.0)
                
                moveInertiaVelocity = CGPoint(x: moveInertiaVelocity.x * decay, y: moveInertiaVelocity.y * decay)
                let speed = hypot(moveInertiaVelocity.x, moveInertiaVelocity.y)
                
                if speed < 40.0 {
                    moveInertiaVelocity = .zero
                } else {
                    let delta = CGPoint(x: moveInertiaVelocity.x * CGFloat(dt), y: moveInertiaVelocity.y * CGFloat(dt))
                    pointer.moveRelativePercentage(by: scaledDelta(delta))
                }
            }
        }
        
        // 2. Scroll Inertia
        if scrollInertiaVelocity != .zero {
            let decelerationRate: CGFloat = 0.95
            let decay = pow(decelerationRate, CGFloat(dt) * 60.0)
            
            scrollInertiaVelocity = CGPoint(
                x: scrollInertiaVelocity.x * decay,
                y: scrollInertiaVelocity.y * decay
            )
            let speed = hypot(scrollInertiaVelocity.x, scrollInertiaVelocity.y)
            
            if speed < 40.0 {
                scrollInertiaVelocity = .zero
            } else {
                let delta = CGPoint(
                    x: scrollInertiaVelocity.x * CGFloat(dt),
                    y: -(scrollInertiaVelocity.y * CGFloat(dt))
                )
                pointer.scroll(delta: normalizedScrollDelta(delta))
            }
        }
        
        checkInertiaState()
    }

    private func normalizedScrollDelta(_ delta: CGPoint) -> CGPoint {
        // Normalize scroll delta based on view height to achieve resolution independence.
        // A reference height of 800 points is used.
        let referenceHeight: CGFloat = 800.0
        let scale = referenceHeight / max(1.0, bounds.height)
        
        // Apply sensitivity multiplier
        let sensitivity: CGFloat = 3.5
        
        return CGPoint(x: delta.x * scale * sensitivity, y: delta.y * scale * sensitivity)
    }

    private func scaledDelta(_ delta: CGPoint) -> CGPoint {
        guard inputMode == .trackpad else {
            return delta
        }

        return CGPoint(x: delta.x * trackpadMoveMultiplier, y: delta.y * trackpadMoveMultiplier)
    }
}
#endif
