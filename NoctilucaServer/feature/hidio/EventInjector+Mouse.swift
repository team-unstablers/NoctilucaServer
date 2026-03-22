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
                self.performMouseMoveAbsoluteOnQueue(percentage: position, scope: event.scope, pressure: event.pressure)
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
        
        DispatchQueue.main.async {
            CursorStateHolder.shared.updateCursorPosition()
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
    
    private func performMouseMoveAbsoluteOnQueue(percentage position: CursorPositionPercent, scope: CursorPositionScope, pressure: Int32? = nil) {
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
        
        let displayLayoutManager = DisplayLayoutManager.shared
        let layouts = displayLayoutManager.displayLayouts.snapshot()
        let mainScreen = layouts[CGMainDisplayID()]
        let targetScreen = layouts[displayID] ?? mainScreen
        
        guard let screen = targetScreen else {
            return
        }
        
        let x11Point = CGPoint(
            x: screen.frame.minX + (screen.frame.width * CGFloat(position.x)),
            y: screen.frame.minY + (screen.frame.height * CGFloat(position.y))
        )
        
        let clampedX11 = CursorState.clampToNearestScreen(x11Point, layouts: layouts)
        let position = mainScreen.map { CursorState.toCoreGraphicsCoordinate(clampedX11, mainScreen: $0) } ?? clampedX11

        if (mouseDownState & EventInjector.MOUSE_DOWN_STATE_LEFT > 0) {
            mouseType = .leftMouseDragged
        } else if (mouseDownState & EventInjector.MOUSE_DOWN_STATE_RIGHT > 0) {
            mouseType = .rightMouseDragged
        }
        
        if !hack_tabletEvent {
            guard let event = CGEvent(mouseEventSource: nil,
                                              mouseType: .mouseMoved,
                                              mouseCursorPosition: position,
                                              mouseButton: .left) else { return }
                    
            event.type = .tabletProximity
            
            // 타블렛 장치 및 펜 정보 세팅
            event.setIntegerValueField(.tabletProximityEventVendorID, value: 1) // 가상 벤더 ID
            event.setIntegerValueField(.tabletProximityEventTabletID, value: 0x8181)
            event.setIntegerValueField(.tabletProximityEventPointerID, value: 0x8383)
            event.setIntegerValueField(.tabletProximityEventDeviceID, value: 0x8282)
            event.setIntegerValueField(.tabletProximityEventSystemTabletID, value: 0x8181)
            
            // 포인터 타입 (1: 일반 펜 촉, 2: 펜 뒤쪽 지우개, 3: 마우스)
            event.setIntegerValueField(.tabletProximityEventPointerType, value: 1)
            
            // 인식 범위 진입 여부 (1: 들어옴, 0: 나감)
            event.setIntegerValueField(.tabletProximityEventEnterProximity, value: 1)
            
            
            event.setDoubleValueField(.mouseEventPressure, value: 0)
            event.setDoubleValueField(.tabletEventPointPressure, value: 0)

            event.post(tap: .cgSessionEventTap)
            
            hack_tabletEvent = true
        }
        
        guard let cgEvent = CGEvent(
                mouseEventSource: eventSource,
                mouseType: .mouseMoved,
                mouseCursorPosition: position,
                mouseButton: mouseButton
        )
        else {
            return
        }
        
        cgEvent.type = .tabletPointer

        cgEvent.sanitizeModifierFlags(with: keyDownState)
        
        if let pressure32 = pressure {
            let fpPressure = Double.minimum((Double(pressure32) / 8192.0), 1.0)
            // print(fpPressure)
            cgEvent.setIntegerValueField(.tabletEventDeviceID, value: 0x8282)
            cgEvent.setIntegerValueField(.tabletEventPointButtons, value: 1)
            cgEvent.setDoubleValueField(.mouseEventPressure, value: fpPressure)
            cgEvent.setDoubleValueField(.tabletEventPointPressure, value: fpPressure)
        }
        
        cgEvent.post(tap: .cgSessionEventTap)
        
        if (mouseDownState & EventInjector.MOUSE_DOWN_STATE_LEFT > 0) {
            guard let cgEvent = CGEvent(
                mouseEventSource: eventSource,
                mouseType: .leftMouseDown,
                mouseCursorPosition: position,
                mouseButton: mouseButton
            )
            else {
                return
            }
            
            // cgEvent.type = .tabletPointer
            
            cgEvent.sanitizeModifierFlags(with: keyDownState)
            
            if let pressure32 = pressure {
                let fpPressure = Double.minimum((Double(pressure32) / 8192.0), 1.0)
                // print(fpPressure)
                cgEvent.setIntegerValueField(.tabletEventDeviceID, value: 0x8282)
                cgEvent.setIntegerValueField(.tabletEventPointButtons, value: 1)
                cgEvent.setDoubleValueField(.mouseEventPressure, value: fpPressure)
                cgEvent.setDoubleValueField(.tabletEventPointPressure, value: fpPressure)
            }
            
            cgEvent.post(tap: .cgSessionEventTap)
        } else {
            guard let cgEvent = CGEvent(
                mouseEventSource: eventSource,
                mouseType: .leftMouseUp,
                mouseCursorPosition: position,
                mouseButton: mouseButton
            )
            else {
                return
            }
            
            // cgEvent.type = .tabletPointer
            
            cgEvent.sanitizeModifierFlags(with: keyDownState)
            
            if let pressure32 = pressure {
                let fpPressure = Double.minimum((Double(pressure32) / 8192.0), 1.0)
                // print(fpPressure)
                cgEvent.setIntegerValueField(.tabletEventDeviceID, value: 0x8282)
                cgEvent.setIntegerValueField(.tabletEventPointButtons, value: 1)
                cgEvent.setDoubleValueField(.mouseEventPressure, value: fpPressure)
                cgEvent.setDoubleValueField(.tabletEventPointPressure, value: fpPressure)
            }
            
            cgEvent.post(tap: .cgSessionEventTap)
        }

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
        
        let displayLayoutManager = DisplayLayoutManager.shared
        let layouts = displayLayoutManager.displayLayouts.snapshot()
        let mainScreen = layouts[CGMainDisplayID()]
        
        let currentCGPosition = event.location
        let currentX11Position = mainScreen.map {
            CursorState.toX11Coordinate(currentCGPosition, mainScreen: $0)
        } ?? currentCGPosition
        
        let targetX11Position = CGPoint(
            x: currentX11Position.x + CGFloat(position.x),
            y: currentX11Position.y + CGFloat(position.y)
        )
        
        let clampedX11Position = CursorState.clampToNearestScreen(targetX11Position, layouts: layouts)
        let position = mainScreen.map {
            CursorState.toCoreGraphicsCoordinate(clampedX11Position, mainScreen: $0)
        } ?? clampedX11Position
        
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
        
        let displayLayoutManager = DisplayLayoutManager.shared
        let layouts = displayLayoutManager.displayLayouts.snapshot()
        let mainScreen = layouts[CGMainDisplayID()]
        
        let currentCGPosition = event.location
        let currentX11Position = mainScreen.map {
            CursorState.toX11Coordinate(currentCGPosition, mainScreen: $0)
        } ?? currentCGPosition
        
        let screenFrame: CGRect
        if let screen = layouts.first(where: { $0.value.frame.contains(currentX11Position) })?.value {
            screenFrame = screen.frame
        } else if let mainScreen {
            screenFrame = mainScreen.frame
        } else {
            screenFrame = CGRect(origin: .zero, size: displayLayoutManager.globalFrame.size)
        }
        
        let targetX11Position = CGPoint(
            x: currentX11Position.x + (CGFloat(position.x) * screenFrame.size.width),
            y: currentX11Position.y + (CGFloat(position.y) * screenFrame.size.height)
        )
        
        let clampedX11Position = CursorState.clampToNearestScreen(targetX11Position, layouts: layouts)
        let position = mainScreen.map {
            CursorState.toCoreGraphicsCoordinate(clampedX11Position, mainScreen: $0)
        } ?? clampedX11Position

        

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
        var cgMouseButton: CGMouseButton = .left

        switch event.button {
        case .left:
            mouseType = (event.eventType == .up ? .leftMouseUp : .leftMouseDown)
            cgMouseButton = .left
            mouseDownState =
                (mouseDownState & EventInjector.MOUSE_DOWN_STATE_RIGHT) |
                (event.eventType == .up ? 0b0 : EventInjector.MOUSE_DOWN_STATE_LEFT)
        case .right:
            mouseType = (event.eventType == .up ? .rightMouseUp : .rightMouseDown)
            cgMouseButton = .right
            mouseDownState =
                (mouseDownState & EventInjector.MOUSE_DOWN_STATE_LEFT) |
                (event.eventType == .up ? 0b0 : EventInjector.MOUSE_DOWN_STATE_RIGHT)
        default:
            break
        }

        guard let cgEvent = CGEvent(
            mouseEventSource: eventSource,
            mouseType: mouseType,
            mouseCursorPosition: lastMousePosition ?? CGEvent(source: nil)!.location,
            mouseButton: cgMouseButton
        )
        else {
            return
        }

        if event.eventType == .down {
            let now = Date().timeIntervalSince1970
            let sameButton = (event.button.rawValue == lastClickButton)
            let withinInterval = (now - lastClickTime) < NSEvent.doubleClickInterval

            if sameButton && withinInterval && clickCount < 3 {
                clickCount += 1
            } else {
                clickCount = 1
            }

            lastClickButton = event.button.rawValue
            lastClickTime = now
        }
        
        
        cgEvent.setIntegerValueField(.tabletEventDeviceID, value: 0x8282)
        cgEvent.setDoubleValueField(.mouseEventPressure, value: 0.0)
        cgEvent.setDoubleValueField(.tabletEventPointPressure, value: 0.0)

        cgEvent.setIntegerValueField(.mouseEventClickState, value: clickCount)
        cgEvent.sanitizeModifierFlags(with: keyDownState)
        // cgEvent.post(tap: .cgSessionEventTap)
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
