//
//  HIDIO.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import SiriusKit

class HIDIOChannel: Channel {
    required init(using streamHolder: StreamHolder, identifier: ChannelIdentifier, direction: ChannelDirection) {
        super.init(using: streamHolder, identifier: identifier, direction: direction)
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
}
