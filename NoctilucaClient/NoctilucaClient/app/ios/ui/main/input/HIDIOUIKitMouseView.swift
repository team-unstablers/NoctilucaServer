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

    var body: some View {
        HIDIOUIKitMouseCaptureView(
            pointer: mouse,
            mode: $mode,
            trackpadMoveMultiplier: $trackpadMoveMultiplier
        )
    }
}

private struct HIDIOUIKitMouseCaptureView: UIViewRepresentable {
    let pointer: HIDIOUIKitMouse
    
    @Binding var mode: AppSettings.TouchInputMode
    @Binding var trackpadMoveMultiplier: Double

    func makeUIView(context: Context) -> MouseInputCaptureView {
        let view = MouseInputCaptureView(pointer: pointer)
        view.updateInputMode(mode, trackpadMoveMultiplier: trackpadMoveMultiplier)
        return view
    }

    func updateUIView(_ uiView: MouseInputCaptureView, context: Context) {
        uiView.updateInputMode(mode, trackpadMoveMultiplier: trackpadMoveMultiplier)
    }
}

private final class MouseInputCaptureView: UIView, UIGestureRecognizerDelegate {
    private let pointer: HIDIOUIKitMouse
    private var inputMode: AppSettings.TouchInputMode = .touch
    private var trackpadMoveMultiplier: CGFloat = 1.0

    private let tapRecognizer = UITapGestureRecognizer()
    private let twoFingerTapRecognizer = UITapGestureRecognizer()
    private let panRecognizer = UIPanGestureRecognizer()
    private let twoFingerPanRecognizer = UIPanGestureRecognizer()
    private let chordedDragRecognizer = ChordedDragGestureRecognizer()

    private var isChordedDragging: Bool = false
    private var isScrolling: Bool = false
    
    // Unified Inertia Engine
    private var inertiaDisplayLink: CADisplayLink?
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
        stopInertiaLoop()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pointer.updateGeometry(bounds.size)
    }

    func updateInputMode(_ mode: AppSettings.TouchInputMode, trackpadMoveMultiplier: Double) {
        inputMode = mode
        self.trackpadMoveMultiplier = max(0.1, CGFloat(trackpadMoveMultiplier))
        if mode != .trackpad {
            moveInertiaVelocity = .zero
        }
        scrollInertiaVelocity = .zero
        checkInertiaState()
        // No explicit configureRecognizerState() needed as delegate handles it dynamically.
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
    }

    // MARK: - Touch Handling (Direct)
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard inputMode == .touch, let touch = touches.first, event?.allTouches?.count == 1 else {
            super.touchesBegan(touches, with: event)
            return
        }
        
        let location = touch.location(in: self)
        pointer.moveAbsolute(to: location)
        pointer.buttonDown(.left)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard inputMode == .touch, let touch = touches.first, event?.allTouches?.count == 1 else {
            super.touchesMoved(touches, with: event)
            return
        }
        
        let location = touch.location(in: self)
        pointer.moveAbsolute(to: location)
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard inputMode == .touch, let touch = touches.first else {
            super.touchesEnded(touches, with: event)
            return
        }
        
        // Ensure we lift the button even if it transitioned to multi-touch, 
        // but typically we care about the primary finger lifting.
        let location = touch.location(in: self)
        pointer.moveAbsolute(to: location)
        pointer.buttonUp(.left)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard inputMode == .touch, let touch = touches.first else {
            super.touchesCancelled(touches, with: event)
            return
        }
        
        let location = touch.location(in: self)
        pointer.moveAbsolute(to: location)
        pointer.buttonUp(.left)
    }

    // MARK: - UIGestureRecognizerDelegate
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
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

        switch inputMode {
        case .touch:
            // Should be handled by PanRecognizer in .began
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
            let location = averageLocation(for: recognizer)
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
            let link = CADisplayLink(target: self, selector: #selector(handleInertiaTick(_:)))
            link.add(to: .main, forMode: .common)
            inertiaDisplayLink = link
        }
        inertiaDisplayLink?.isPaused = false
    }

    private func stopInertiaLoop() {
        inertiaDisplayLink?.invalidate()
        inertiaDisplayLink = nil
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

    @objc private func handleInertiaTick(_ link: CADisplayLink) {
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
