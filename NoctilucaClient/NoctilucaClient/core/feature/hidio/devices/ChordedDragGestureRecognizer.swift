//
//  ChordedDragGestureRecognizer.swift
//  NoctilucaClient
//
//  Created by Codex on 1/29/26.
//

#if os(iOS)
import UIKit

final class ChordedDragGestureRecognizer: UIGestureRecognizer {
    var maximumSecondTouchInterval: TimeInterval = 0.12
    var maximumFirstTouchMovement: CGFloat = 8.0

    private var firstTouch: UITouch?
    private var secondTouch: UITouch?
    private var firstTouchStartLocation: CGPoint = .zero
    private var lastSecondTouchLocation: CGPoint = .zero
    private var timeoutTimer: Timer?

    private(set) var translation: CGPoint = .zero

    override func reset() {
        super.reset()
        firstTouch = nil
        secondTouch = nil
        firstTouchStartLocation = .zero
        lastSecondTouchLocation = .zero
        translation = .zero
        invalidateTimeout()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let view else {
            state = .failed
            return
        }

        if firstTouch == nil, let touch = touches.first {
            firstTouch = touch
            firstTouchStartLocation = touch.location(in: view)
            scheduleTimeout()
            return
        }

        if secondTouch == nil, let touch = touches.first {
            guard let firstTouch else {
                state = .failed
                return
            }

            let interval = touch.timestamp - firstTouch.timestamp
            if interval > maximumSecondTouchInterval {
                state = .failed
                return
            }

            let currentFirstLocation = firstTouch.location(in: view)
            if distance(from: firstTouchStartLocation, to: currentFirstLocation) > maximumFirstTouchMovement {
                state = .failed
                return
            }

            secondTouch = touch
            lastSecondTouchLocation = touch.location(in: view)
            translation = .zero
            invalidateTimeout()
            state = .began
            return
        }

        state = .failed
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let view else {
            state = .failed
            return
        }

        if secondTouch == nil, let firstTouch {
            let location = firstTouch.location(in: view)
            if distance(from: firstTouchStartLocation, to: location) > maximumFirstTouchMovement {
                invalidateTimeout()
                state = .failed
            }
            return
        }

        guard state == .began || state == .changed else {
            return
        }

        guard let secondTouch else {
            state = .failed
            return
        }

        let location = secondTouch.location(in: view)
        translation = CGPoint(x: location.x - lastSecondTouchLocation.x, y: location.y - lastSecondTouchLocation.y)
        lastSecondTouchLocation = location
        state = .changed
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if touches.contains(where: { $0 == firstTouch || $0 == secondTouch }) {
            if state == .began || state == .changed {
                state = .ended
            } else {
                state = .failed
            }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }

    private func scheduleTimeout() {
        invalidateTimeout()
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: maximumSecondTouchInterval, repeats: false) { [weak self] _ in
            guard let self else {
                return
            }
            if self.state == .possible && self.secondTouch == nil {
                self.state = .failed
            }
        }
    }

    private func invalidateTimeout() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }

    private func distance(from: CGPoint, to: CGPoint) -> CGFloat {
        let dx = to.x - from.x
        let dy = to.y - from.y
        return sqrt(dx * dx + dy * dy)
    }
}
#endif
