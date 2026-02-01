//
//  ChordedDragGestureRecognizer.swift
//  NoctilucaClient
//
//  Created by Codex on 1/29/26.
//

#if os(iOS)
import UIKit

final class ChordedDragGestureRecognizer: UIGestureRecognizer {
    var maximumFirstTouchMovement: CGFloat = 8.0

    private var firstTouch: UITouch?
    private var secondTouch: UITouch?
    private var firstTouchStartLocation: CGPoint = .zero
    private var lastSecondTouchLocation: CGPoint = .zero

    private(set) var translation: CGPoint = .zero

    override func reset() {
        super.reset()
        firstTouch = nil
        secondTouch = nil
        firstTouchStartLocation = .zero
        lastSecondTouchLocation = .zero
        translation = .zero
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let view else {
            state = .failed
            return
        }

        if firstTouch == nil, let touch = touches.first {
            firstTouch = touch
            firstTouchStartLocation = touch.location(in: view)
            return
        }

        if secondTouch == nil, let touch = touches.first {
            // Check if this is the first touch being re-added (unlikely but safe to check)
            if touch == firstTouch { return }
            
            // Allow second touch to be added even if first touch moved significantly?
            // For continuous drag, we should probably allow it.
            // The distance check from firstTouchStartLocation might be too strict for re-entry.
            // Let's remove the strict distance check for re-entry or relax it?
            // Actually, if we want "Tap-Hold A -> Drag B -> Lift B -> Drag B", A usually stays still.
            // But if A moved a bit, it shouldn't block B.
            
            secondTouch = touch
            lastSecondTouchLocation = touch.location(in: view)
            
            // If we are already in began/changed state, we just continue (or resume).
            // If we haven't started (e.g. first touch was just sitting there), we start now.
            if state == .possible {
                translation = .zero
                state = .began
            } else {
                // If we were already active (kept alive by first touch), this is a resumption.
                // We don't change state to .began again if it's already running, 
                // but UIGestureRecognizer state machine might need care.
                // Standard recognizers usually stay in .changed.
                // We set translation to zero for this new segment?
                // Or we just update lastSecondTouchLocation and wait for move.
                // Let's ensure state is .changed if it was somehow paused?
                // Actually, if we keep state as .began/.changed when B lifts, 
                // we just continue emitting .changed events.
                state = .changed
            }
            return
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let view else {
            state = .failed
            return
        }

        // If second touch is active, track it
        if let second = secondTouch, touches.contains(second) {
            // Start or Continue drag
            if state == .possible {
                // Should have been started in touchesBegan, but just in case
                state = .began
            }
            
            let location = second.location(in: view)
            translation = CGPoint(x: location.x - lastSecondTouchLocation.x, y: location.y - lastSecondTouchLocation.y)
            lastSecondTouchLocation = location
            state = .changed
            return
        }
        
        // If only first touch moved
        if let first = firstTouch, touches.contains(first) {
            let location = first.location(in: view)
            // If we are already dragging (state == .began/changed), moving the anchor finger usually doesn't fail the gesture 
            // in standard "hold and drag" patterns, but might shift the cursor if mapped.
            // For now, let's allow anchor movement if gesture already started.
            // Only check movement limit if we haven't started yet.
            if state == .possible {
                if distance(from: firstTouchStartLocation, to: location) > maximumFirstTouchMovement {
                    state = .failed
                }
            }
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let first = firstTouch, touches.contains(first) {
            // First touch lifted -> End the gesture
            if state == .began || state == .changed {
                state = .ended
            } else {
                state = .failed
            }
            return
        }
        
        if let second = secondTouch, touches.contains(second) {
            // Second touch lifted -> Pause drag, but keep gesture active
            secondTouch = nil
            // We don't set state to .ended. We stay in .changed (or .began).
            // This allows the user to put the finger down again.
            
            // Optionally, we could fire a final "zero" delta or just stop firing.
            // Since we report relative translation in touchesMoved, just stopping updates is enough.
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .cancelled
    }

    private func distance(from: CGPoint, to: CGPoint) -> CGFloat {
        let dx = to.x - from.x
        let dy = to.y - from.y
        return sqrt(dx * dx + dy * dy)
    }
}
#endif
