//
//  EventInjector.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/11/25.
//

import Foundation

import Carbon
import Cocoa
import CoreGraphics

import SiriusKit

extension EventInjector {
    func post(mouseMoveEvent event: MouseMoveEvent, scaleX: Double = 1.0, scaleY: Double = 1.0) {
        enqueue { [weak self] in
            self?.postMouseMoveEventOnQueue(event, scaleX: scaleX, scaleY: scaleY)
        }
    }
    
    private func postMouseMoveEventOnQueue(_ event: MouseMoveEvent, scaleX: Double, scaleY: Double) {
        switch event.moveType {
        case .absolute:
            switch event.position {
            case .percent(let position):
                self.performMouseMoveAbsoluteOnQueue(percentage: position, scope: event.scope)
            case .pixel:
                // TODO: Implement absolute pixel movement if needed (usually weird in multi-monitor)
                break
            }
        case .relative:
            switch event.position {
            case .pixel(let position):
                self.performMouseMoveRelativeOnQueue(pixel: position)
            case .percent(let position):
                self.performMouseMoveRelativeOnQueue(percentage: position)
            }
        default:
            return
        }
    }
    
    func performMouseMoveAbsolute(percentage position: CursorPositionPercent) {
        enqueue { [weak self] in
            // Defaulting to Main Display for backward compatibility
            self?.performMouseMoveAbsoluteOnQueue(
                percentage: position,
                scope: .displayId(Int32(CGMainDisplayID()))
            )
        }
    }
    
    private func performMouseMoveAbsoluteOnQueue(percentage position: CursorPositionPercent, scope: CursorPositionScope) {
        var mouseType: CGEventType = .mouseMoved
        var mouseButton: CGMouseButton = .left
        
        let displayID: CGDirectDisplayID
        switch scope {
        case .displayId(let id):
            if id == -1 {
                displayID = CGMainDisplayID()
            } else {
                displayID = CGDirectDisplayID(UInt32(bitPattern: id))
            }
        default:
            displayID = CGMainDisplayID()
        }
        
        guard let globalPoint = DisplayLayoutManager.shared.globalPoint(
            fromPercent: CGPoint(x: CGFloat(position.x), y: CGFloat(position.y)),
            on: displayID
        ) else {
            return
        }
        
        let position = globalPoint

        if (mouseDownState & EventInjector.MOUSE_DOWN_STATE_LEFT > 0) {
            mouseType = .leftMouseDragged
        } else if (mouseDownState & EventInjector.MOUSE_DOWN_STATE_RIGHT > 0) {
            mouseType = .rightMouseDragged
        }

        guard let cgEvent = CGEvent(
                mouseEventSource: eventSource,
                mouseType: mouseType,
                mouseCursorPosition: position,
                mouseButton: mouseButton
        )
        else {
            return
        }

        cgEvent.sanitizeModifierFlags(with: keyDownState)
        cgEvent.post(tap: .cgSessionEventTap)

        lastMousePosition = position
        
    }
    
    func performMouseMoveRelative(pixel position: CursorPositionPixel) {
        enqueue { [weak self] in
            self?.performMouseMoveRelativeOnQueue(pixel: position)
        }
    }
    
    private func performMouseMoveRelativeOnQueue(pixel position: CursorPositionPixel) {
        var mouseType: CGEventType = .mouseMoved
        var mouseButton: CGMouseButton = .left
        
        guard let event = CGEvent(source: nil) else {
            return
        }
        
        let currentPosition = event.location

        let position = CGPoint(
            x: currentPosition.x + CGFloat(position.x),
            y: currentPosition.y + CGFloat(position.y)
        )

        if (mouseDownState & EventInjector.MOUSE_DOWN_STATE_LEFT > 0) {
            mouseType = .leftMouseDragged
        } else if (mouseDownState & EventInjector.MOUSE_DOWN_STATE_RIGHT > 0) {
            mouseType = .rightMouseDragged
        }

        guard let cgEvent = CGEvent(
                mouseEventSource: eventSource,
                mouseType: mouseType,
                mouseCursorPosition: position,
                mouseButton: mouseButton
        )
        else {
            return
        }

        cgEvent.sanitizeModifierFlags(with: keyDownState)
        cgEvent.post(tap: .cgSessionEventTap)

        lastMousePosition = position
        
    }
    
    func performMouseMoveRelative(percentage position: CursorPositionPercent) {
        enqueue { [weak self] in
            self?.performMouseMoveRelativeOnQueue(percentage: position)
        }
    }
    
    private func performMouseMoveRelativeOnQueue(percentage position: CursorPositionPercent) {
        var mouseType: CGEventType = .mouseMoved
        var mouseButton: CGMouseButton = .left
        
        guard let event = CGEvent(source: nil) else {
            return
        }
        
        let currentPosition = event.location
        
        // Find which screen contains currentPosition
        // We use DisplayLayoutManager to find the screen (NOCScreen) for X11-like global coordinates
        // Assuming currentPosition is in global coordinates (Top-Left 0,0)
        
        let screenFrame: CGRect
        if let (displayID, _) = DisplayLayoutManager.shared.resolveRelativePoint(point: currentPosition),
           let screen = DisplayLayoutManager.shared.layoutStorage.get(displayID) {
            screenFrame = screen.frame
        } else {
            // Fallback to Main Display
            screenFrame = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        }
        
        let position = CGPoint(
            x: currentPosition.x + (CGFloat(position.x) * screenFrame.size.width),
            y: currentPosition.y + (CGFloat(position.y) * screenFrame.size.height)
        )

        

        if (mouseDownState & EventInjector.MOUSE_DOWN_STATE_LEFT > 0) {
            mouseType = .leftMouseDragged
        } else if (mouseDownState & EventInjector.MOUSE_DOWN_STATE_RIGHT > 0) {
            mouseType = .rightMouseDragged
        }

        guard let cgEvent = CGEvent(
                mouseEventSource: eventSource,
                mouseType: mouseType,
                mouseCursorPosition: position,
                mouseButton: mouseButton
        )
        else {
            return
        }

        cgEvent.sanitizeModifierFlags(with: keyDownState)
        cgEvent.post(tap: .cgSessionEventTap)

        lastMousePosition = position

    }


    func post(mouseButtonEvent event: MouseButtonEvent) {
        enqueue { [weak self] in
            self?.postMouseButtonEventOnQueue(event)
        }
    }
    
    private func postMouseButtonEventOnQueue(_ event: MouseButtonEvent) {
        var mouseType: CGEventType = .null
        

        switch (event.button) {
        case .left:
            let mask = EventInjector.MOUSE_DOWN_STATE_LEFT

            mouseType = (event.eventType == .up ? .leftMouseUp : .leftMouseDown)
            mouseDownState =
                    (mouseDownState & EventInjector.MOUSE_DOWN_STATE_RIGHT) |
                    (event.eventType == .up ? 0b0 : EventInjector.MOUSE_DOWN_STATE_LEFT)
            break
        case .right:
            let mask = EventInjector.MOUSE_DOWN_STATE_RIGHT

            mouseType = (event.eventType == .up ? .rightMouseUp : .rightMouseDown)
            mouseDownState =
                    (mouseDownState & EventInjector.MOUSE_DOWN_STATE_LEFT) |
                    (event.eventType == .up ? 0b0 : EventInjector.MOUSE_DOWN_STATE_RIGHT)
            break

        default:
            break
        }

        guard let cgEvent = CGEvent(
                mouseEventSource: eventSource,
                mouseType: mouseType,
                mouseCursorPosition: lastMousePosition ?? CGEvent(source: nil)!.location,
                mouseButton: .center
        )
        else {
            return
        }

        let now = Date().timeIntervalSince1970
        if (event.eventType == .up) {
            // double click을 에뮬레이트 했어야 했던 걸로 기억한다
            if ((now - mouseClickedAt) < 0.5) {
                cgEvent.setIntegerValueField(.mouseEventClickState, value: 2)
            }

            mouseClickedButton = Int64(event.button.rawValue)
            mouseClickedAt = now
        }

        cgEvent.sanitizeModifierFlags(with: keyDownState)
        cgEvent.post(tap: .cgSessionEventTap)
    }

    func post(mouseWheelEvent event: MouseWheelEvent) {
        enqueue { [weak self] in
            self?.postMouseWheelEventOnQueue(event)
        }
    }
    
    private func postMouseWheelEventOnQueue(_ event: MouseWheelEvent) {
        var mouseType: CGEventType = .null
        
        guard let cgEvent = CGEvent(
                scrollWheelEvent2Source: eventSource,
                units: .pixel,
                wheelCount: abs(event.deltaY) > abs(event.deltaX) ? 1 : 2,
                wheel1: Int32(-event.deltaY),
                wheel2: Int32(event.deltaX),
                wheel3: 0
        )
        else {
            return
        }

        cgEvent.sanitizeModifierFlags(with: keyDownState)
        cgEvent.post(tap: .cgSessionEventTap)
    }
}
