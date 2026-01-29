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
    let client: NoctilucaClient?
    @Binding var mode: AppSettings.TouchInputMode
    @Binding var trackpadMoveMultiplier: Double
    @Binding var cursorPosition: CGPoint
    @Binding var aspectRatio: CGFloat

    @State private var pointer = HIDIOUIKitPointer()

    var body: some View {
        VStack(alignment: .center) {
            if let client {
                Spacer()
                HIDIOUIKitMouseCaptureView(
                    pointer: pointer,
                    mode: $mode,
                    trackpadMoveMultiplier: $trackpadMoveMultiplier
                )
                    .aspectRatio(aspectRatio, contentMode: .fit)
                    .onAppear {
                        pointer.onCursorPositionChanged = { position in
                            cursorPosition = position
                        }
                        connectPointerIfNeeded(client)
                    }
                    .onDisappear {
                        disconnectPointer(client)
                    }
                    .onReceive(client.uiEvents) { event in
                        guard case .FIXME_projectionStarted(let projectionSession) = event else {
                            return
                        }

                        connectPointerIfNeeded(client)

                        // FIXME: 레이스 컨디션
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            let size = projectionSession.size
                            aspectRatio = size.width / size.height
                        }
                    }
                Spacer()
            } else {
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func connectPointerIfNeeded(_ client: NoctilucaClient) {
        guard let controller = client.hidioController else {
            return
        }

        controller.connect(pointer)
    }

    private func disconnectPointer(_ client: NoctilucaClient) {
        client.hidioController?.disconnect(.uiKitPointer)
        pointer.disconnect()
    }
}

private struct HIDIOUIKitMouseCaptureView: UIViewRepresentable {
    let pointer: HIDIOUIKitPointer
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
    private let pointer: HIDIOUIKitPointer
    private var inputMode: AppSettings.TouchInputMode = .touch
    private var trackpadMoveMultiplier: CGFloat = 1.0

    private let tapRecognizer = UITapGestureRecognizer()
    private let twoFingerTapRecognizer = UITapGestureRecognizer()
    private let panRecognizer = UIPanGestureRecognizer()
    private let twoFingerPanRecognizer = UIPanGestureRecognizer()
    private let longPressRecognizer = UILongPressGestureRecognizer()
    private let chordedDragRecognizer = ChordedDragGestureRecognizer()

    private var lastPanTranslation: CGPoint = .zero
    private var lastScrollTranslation: CGPoint = .zero
    private var lastLongPressLocation: CGPoint = .zero
    private var isLongPressDragging: Bool = false
    private var isChordedDragging: Bool = false
    private var moveInertiaDisplayLink: CADisplayLink?
    private var moveInertiaVelocity: CGPoint = .zero
    private var moveInertiaLastTimestamp: CFTimeInterval?

    // Scroll Inertia
    private var scrollInertiaDisplayLink: CADisplayLink?
    private var scrollInertiaVelocity: CGPoint = .zero
    private var scrollInertiaLastTimestamp: CFTimeInterval?

    init(pointer: HIDIOUIKitPointer) {
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
        stopMoveInertia()
        stopScrollInertia()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        pointer.updateGeometry(bounds.size)
    }

    func updateInputMode(_ mode: AppSettings.TouchInputMode, trackpadMoveMultiplier: Double) {
        inputMode = mode
        self.trackpadMoveMultiplier = max(0.1, CGFloat(trackpadMoveMultiplier))
        if mode != .trackpad {
            stopMoveInertia()
        }
        stopScrollInertia()
        configureRecognizerState()
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

        longPressRecognizer.minimumPressDuration = 0.15
        longPressRecognizer.allowableMovement = 10
        longPressRecognizer.addTarget(self, action: #selector(handleLongPress(_:)))

        chordedDragRecognizer.maximumSecondTouchInterval = 0.12
        chordedDragRecognizer.maximumFirstTouchMovement = 8
        chordedDragRecognizer.addTarget(self, action: #selector(handleChordedDrag(_:)))

        tapRecognizer.require(toFail: twoFingerTapRecognizer)
        tapRecognizer.require(toFail: longPressRecognizer)
        panRecognizer.require(toFail: chordedDragRecognizer)

        tapRecognizer.delegate = self
        twoFingerTapRecognizer.delegate = self
        panRecognizer.delegate = self
        twoFingerPanRecognizer.delegate = self
        longPressRecognizer.delegate = self
        chordedDragRecognizer.delegate = self

        addGestureRecognizer(twoFingerTapRecognizer)
        addGestureRecognizer(tapRecognizer)
        addGestureRecognizer(twoFingerPanRecognizer)
        addGestureRecognizer(panRecognizer)
        addGestureRecognizer(longPressRecognizer)
        addGestureRecognizer(chordedDragRecognizer)

        configureRecognizerState()
    }

    private func configureRecognizerState() {
        switch inputMode {
        case .touch:
            tapRecognizer.isEnabled = true
            twoFingerTapRecognizer.isEnabled = true
            panRecognizer.isEnabled = true
            twoFingerPanRecognizer.isEnabled = true
            longPressRecognizer.isEnabled = false
            chordedDragRecognizer.isEnabled = false
        case .trackpad:
            tapRecognizer.isEnabled = true
            twoFingerTapRecognizer.isEnabled = true
            panRecognizer.isEnabled = true
            twoFingerPanRecognizer.isEnabled = true
            longPressRecognizer.isEnabled = true
            chordedDragRecognizer.isEnabled = true
        }
    }

    @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended else {
            return
        }

        switch inputMode {
        case .touch:
            let location = recognizer.location(in: self)
            pointer.moveAbsolute(to: location)
            pointer.buttonDown(.left)
            pointer.buttonUp(.left)
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
        if isLongPressDragging || isChordedDragging {
            return
        }

        switch inputMode {
        case .touch:
            handleTouchDrag(recognizer)
        case .trackpad:
            handleTrackpadMove(recognizer)
        }
    }

    private func handleTouchDrag(_ recognizer: UIPanGestureRecognizer) {
        let location = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            pointer.moveAbsolute(to: location)
            pointer.buttonDown(.left)
        case .changed:
            pointer.moveAbsolute(to: location)
        case .ended, .cancelled, .failed:
            pointer.moveAbsolute(to: location)
            pointer.buttonUp(.left)
        default:
            break
        }
    }

    private func handleTrackpadMove(_ recognizer: UIPanGestureRecognizer) {
        let translation = recognizer.translation(in: self)
        switch recognizer.state {
        case .began:
            stopMoveInertia()
            lastPanTranslation = translation
        case .changed:
            let delta = CGPoint(
                x: translation.x - lastPanTranslation.x,
                y: translation.y - lastPanTranslation.y
            )
            lastPanTranslation = translation
            pointer.moveRelativePercentage(by: scaledDelta(delta))
        case .ended, .cancelled, .failed:
            lastPanTranslation = .zero
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
            stopScrollInertia()
            lastScrollTranslation = translation
        case .changed:
            let delta = CGPoint(
                x: translation.x - lastScrollTranslation.x,
                y: -(translation.y - lastScrollTranslation.y)
            )
            lastScrollTranslation = translation
            pointer.scroll(delta: normalizedScrollDelta(delta))
        case .ended, .cancelled, .failed:
            lastScrollTranslation = .zero
            let velocity = recognizer.velocity(in: self)
            startScrollInertia(with: velocity)
        default:
            break
        }
    }

    @objc private func handleLongPress(_ recognizer: UILongPressGestureRecognizer) {
        guard inputMode == .trackpad else {
            return
        }

        let location = recognizer.location(in: self)
        switch recognizer.state {
        case .began:
            isLongPressDragging = true
            lastLongPressLocation = location
            stopMoveInertia()
            pointer.buttonDown(.left)
        case .changed:
            let delta = CGPoint(x: location.x - lastLongPressLocation.x, y: location.y - lastLongPressLocation.y)
            lastLongPressLocation = location
            pointer.moveRelativePercentage(by: scaledDelta(delta))
        case .ended, .cancelled, .failed:
            isLongPressDragging = false
            pointer.buttonUp(.left)
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
            isChordedDragging = true
            stopMoveInertia()
            pointer.buttonDown(.left)
        case .changed:
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
        guard inputMode == .trackpad else {
            return
        }

        let speed = hypot(velocity.x, velocity.y)
        guard speed >= 40.0 else {
            return
        }

        moveInertiaVelocity = velocity
        moveInertiaLastTimestamp = nil

        if moveInertiaDisplayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(handleMoveInertiaTick(_:)))
            link.add(to: .main, forMode: .common)
            moveInertiaDisplayLink = link
        }
    }

    private func stopMoveInertia() {
        moveInertiaDisplayLink?.invalidate()
        moveInertiaDisplayLink = nil
        moveInertiaVelocity = .zero
        moveInertiaLastTimestamp = nil
    }

    @objc private func handleMoveInertiaTick(_ link: CADisplayLink) {
        guard inputMode == .trackpad else {
            stopMoveInertia()
            return
        }

        let now = link.timestamp
        let last = moveInertiaLastTimestamp ?? now
        let dt = max(0.0, now - last)
        moveInertiaLastTimestamp = now

        // Match the snappy friction from scroll inertia
        let decelerationRate: CGFloat = 0.95
        let decay = pow(decelerationRate, CGFloat(dt) * 60.0)
        
        moveInertiaVelocity = CGPoint(x: moveInertiaVelocity.x * decay, y: moveInertiaVelocity.y * decay)

        let speed = hypot(moveInertiaVelocity.x, moveInertiaVelocity.y)
        if speed < 40.0 {
            stopMoveInertia()
            return
        }

        let delta = CGPoint(x: moveInertiaVelocity.x * CGFloat(dt), y: moveInertiaVelocity.y * CGFloat(dt))
        pointer.moveRelativePercentage(by: scaledDelta(delta))
    }

    private func startScrollInertia(with velocity: CGPoint) {
        let speed = hypot(velocity.x, velocity.y)
        guard speed >= 50.0 else { return }

        scrollInertiaVelocity = velocity
        scrollInertiaLastTimestamp = nil

        if scrollInertiaDisplayLink == nil {
            let link = CADisplayLink(target: self, selector: #selector(handleScrollInertiaTick(_:)))
            link.add(to: .main, forMode: .common)
            scrollInertiaDisplayLink = link
        }
    }

    private func stopScrollInertia() {
        scrollInertiaDisplayLink?.invalidate()
        scrollInertiaDisplayLink = nil
        scrollInertiaVelocity = .zero
        scrollInertiaLastTimestamp = nil
    }

    @objc private func handleScrollInertiaTick(_ link: CADisplayLink) {
        let now = link.timestamp
        let last = scrollInertiaLastTimestamp ?? now
        let dt = max(0.0, now - last)
        scrollInertiaLastTimestamp = now

        // Adjusted friction to mimic the snappy feel of native lists.
        // 0.95 per frame means velocity drops to ~5% after 1 second (0.95^60).
        // This prevents the "sliding on ice" feeling.
        let decelerationRate: CGFloat = 0.95
        let decay = pow(decelerationRate, CGFloat(dt) * 60.0)
        
        scrollInertiaVelocity = CGPoint(
            x: scrollInertiaVelocity.x * decay,
            y: scrollInertiaVelocity.y * decay
        )

        let speed = hypot(scrollInertiaVelocity.x, scrollInertiaVelocity.y)
        // Increased threshold to snap to stop cleanly without crawling
        if speed < 40.0 {
            stopScrollInertia()
            return
        }

        // Apply scroll delta
        let delta = CGPoint(
            x: scrollInertiaVelocity.x * CGFloat(dt),
            y: -(scrollInertiaVelocity.y * CGFloat(dt))
        )
        pointer.scroll(delta: normalizedScrollDelta(delta))
    }

    private func normalizedScrollDelta(_ delta: CGPoint) -> CGPoint {
        // Normalize scroll delta based on view height to achieve resolution independence.
        // A reference height of 800 points is used.
        let referenceHeight: CGFloat = 800.0
        let scale = referenceHeight / max(1.0, bounds.height)
        return CGPoint(x: delta.x * scale, y: delta.y * scale)
    }

    private func scaledDelta(_ delta: CGPoint) -> CGPoint {
        guard inputMode == .trackpad else {
            return delta
        }

        return CGPoint(x: delta.x * trackpadMoveMultiplier, y: delta.y * trackpadMoveMultiplier)
    }
}
#endif
