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
        guard let carbonKeyCode = LinuxKeycode(rawValue: UInt16(keyboardEvent.keyCode)).toCarbonKeycode else {
            return
        }
        
        switch keyboardEvent.eventType {
        case .down:
            eventInjector.performKeyDown(carbonKeyCode, modifiers: 0)
        case .up:
            eventInjector.performKeyUp(carbonKeyCode, modifiers: 0)
        default:
            break
        }
    }
    
    func inject(mouseMoveEvent: MouseMoveEvent) {
        if mouseMoveEvent.moveType == .absolute {
            logger.warning("absolute mouse move is not supported yet")
            return
        }
        
        guard case .displayId(let displayID) = mouseMoveEvent.scope else {
            logger.warning("only screen scope is supported for mouse move")
            return
        }
        
        switch mouseMoveEvent.position {
        case .pixel(let pixelPosition):
            eventInjector.performMouseMoveRelative(pixel: pixelPosition)
        case .percent(let percentPosition):
            break
        }
    }
}
