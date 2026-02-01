//
//  HIDIO.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import SiriusKit

class HIDIOChannel: Channel {
    let logger = NoctilucaLogger(category: "HIDIOChannel")
    
    let eventInjector = EventInjector()
    let cursorStateHolder = CursorStateHolder.shared
    
    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        super.init(using: streamHolder, identifier: identifier, direction: direction)
        
        assert(direction == .remote, "HIDIOChannel must be opened from remote side")
        
        do {
            try eventInjector.prepare()
        } catch {
            logger.error("failed to prepare event injector: \(error.localizedDescription)")
        }
    }
    
    override func handleFrame(frame: SiriusFrame) async throws {
        guard frame.isValid() else {
            throw ChannelError.invalidFrame
        }
        
        // Handle HIDIO specific frames here
        guard frame.opcode == .hidioPacket else {
            throw ChannelError.invalidFrame
        }
        
        let hidioPacket = try HIDIOPacket.fromProtobufBytes(frame.data)
        
        for event in hidioPacket.events {
            switch event {
            case is RawEvent:
                // not implemented
                break
            case is KeyboardSetupEvent:
                // TODO
                break
            case is KeyboardEvent:
                self.inject(keyboardEvent: event as! KeyboardEvent)
                break
            case is MouseMoveEvent:
                self.inject(mouseMoveEvent: event as! MouseMoveEvent)
                break
            case is MouseButtonEvent:
                self.eventInjector.post(mouseButtonEvent: event as! MouseButtonEvent)
                break
            case is MouseWheelEvent:
                self.eventInjector.post(mouseWheelEvent: event as! MouseWheelEvent)
                // self.eventInjector.injectMouseWheelEvent(mouseWheelEvent)
                break
            default:
                break
            }
        }
    }
    
    func inject(keyboardEvent: KeyboardEvent) {
        switch keyboardEvent.eventType {
        case .ucs4:
            injectUcs4Key(keyboardEvent)
        case .keyDown, .keyUp:
            injectNormalKey(keyboardEvent)
        default:
            logger.warning("unhandled keyboard event type: \(keyboardEvent.eventType)")
        }
    }
    
    private func injectNormalKey(_ event: KeyboardEvent) {
        guard let carbonKeyCode = LinuxKeycode(rawValue: UInt16(event.keyCode)).toCarbonKeycode else {
            logger.warning("failed to map linux keycode \(event.keyCode) to carbon keycode")
            return
        }
        
        switch event.eventType {
        case .keyDown:
            eventInjector.postKeyDown(carbonKeyCode)
        case .keyUp:
            eventInjector.postKeyUp(carbonKeyCode)
        default:
            break
        }
    }
    
    private func injectUcs4Key(_ event: KeyboardEvent) {
        eventInjector.postUcs4Input(event.keyCode)
    }
    
    func inject(mouseMoveEvent: MouseMoveEvent) {
        if mouseMoveEvent.moveType == .absolute {
            guard case .displayId(let displayID) = mouseMoveEvent.scope else {
                logger.warning("only screen scope is supported for mouse move")
                return
            }
            
            switch mouseMoveEvent.position {
            case .pixel(let pixelPosition):
                return
            case .percent(let percentPosition):
                eventInjector.performMouseMoveAbsolute(percentage: percentPosition)
                break
            }
        } else {
            guard case .displayId(let displayID) = mouseMoveEvent.scope else {
                logger.warning("only screen scope is supported for mouse move")
                return
            }
            
            switch mouseMoveEvent.position {
            case .pixel(let pixelPosition):
                eventInjector.performMouseMoveRelative(pixel: pixelPosition)
            case .percent(let percentPosition):
                eventInjector.performMouseMoveRelative(percentage: percentPosition)
            }
        }
    }
    
    override func handleStreamClose() {
        eventInjector.resetKeyboardState()
    }
    
    override func handleStreamError(error: (any Error)) {
        eventInjector.resetKeyboardState()
    }
}
