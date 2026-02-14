//
//  HIDIO.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 11/24/25.
//

import SiriusKit
import NoctilucaPluginKit

class HIDIOChannel: Channel {
    let logger = NoctilucaLogger(category: "HIDIOChannel")
    
    let eventInjector = EventInjector()
    let cursorStateHolder = CursorStateHolder.shared
    
    override var serviceClass: ServiceClass { .userInput }

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
                await self.inject(keyboardEvent: event as! KeyboardEvent)
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
    
    func inject(keyboardEvent: KeyboardEvent) async {
        switch keyboardEvent.eventType {
        case .ucs4:
            injectUcs4Key(keyboardEvent)
        case .keyDown, .keyUp:
            await injectNormalKey(keyboardEvent)
        default:
            logger.warning("unhandled keyboard event type: \(keyboardEvent.eventType)")
        }
    }
    
    private func injectNormalKey(_ event: KeyboardEvent) async {
        guard let carbonKeyCode = LinuxKeycode(rawValue: UInt16(event.keyCode)).toCarbonKeycode else {
            logger.warning("failed to map linux keycode \(event.keyCode) to carbon keycode")
            return
        }
        
        let decision = if let hack = HIDIOKeyboardHackRegistry.shared.hacks.first?.value {
            switch event.eventType {
            case .keyDown:
                await hack.onKeyDown(.init(rawValue: UInt16(event.keyCode)))
            case .keyUp:
                await hack.onKeyUp(.init(rawValue: UInt16(event.keyCode)))
            default:
                KeyboardHackResult.passthrough
            }
        } else {
            KeyboardHackResult.passthrough
        }
        
        var newKeyCode = carbonKeyCode
        
        switch decision {
        case .modify(let keyCode):
            newKeyCode = LinuxKeycode(rawValue: UInt16(keyCode.key.rawValue)).toCarbonKeycode!
        case .stop:
            return
        default:
            break
        }
        
        switch event.eventType {
        case .keyDown:
            eventInjector.postKeyDown(newKeyCode)
        case .keyUp:
            eventInjector.postKeyUp(newKeyCode)
        default:
            break
        }
    }
    
    private func injectUcs4Key(_ event: KeyboardEvent) {
        eventInjector.postUcs4Input(event.keyCode)
    }
    
    func inject(mouseMoveEvent: MouseMoveEvent) {
        eventInjector.post(mouseMoveEvent: mouseMoveEvent)
    }
    
    override func handleStreamClose() {
        eventInjector.resetKeyboardState()
    }
    
    override func handleStreamError(error: (any Error)) {
        eventInjector.resetKeyboardState()
    }
}
