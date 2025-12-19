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
        
        for eventContainer in hidioPacket.events {
            switch eventContainer.event {
            case .rawEvent(_):
                // not implemented
                break
            case .keyboardSetupEvent(let keyboardSetupEvent):
                // TODO
                break
            case .keyboardEvent(let keyboardEvent):
                self.inject(keyboardEvent: keyboardEvent)
                // self.eventInjector.injectKeyboardEvent(keyboardEvent)
                break
            case .mouseMoveEvent(let mouseMoveEvent):
                // self.eventInjector.injectMouseMoveEvent(mouseMoveEvent)
                break
            case .mouseButtonEvent(let mouseButtonEvent):
                // self.eventInjector.injectMouseButtonEvent(mouseButtonEvent)
                break
            case .mouseWheelEvent(let mouseWheelEvent):
                // self.eventInjector.injectMouseWheelEvent(mouseWheelEvent)
                break
            case .none:
                fallthrough
            @unknown default:
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
}
