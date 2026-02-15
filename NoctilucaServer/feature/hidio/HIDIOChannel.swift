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
    
    private var keyboardHacks: [KeyboardHackPluginV1] = []
    
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
                await self.handleKeyboardSetupEvent(event as! KeyboardSetupEvent)
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
    
    func handleKeyboardSetupEvent(_ event: KeyboardSetupEvent) async {
        let registry = HIDIOKeyboardHackRegistry.shared
        
        self.keyboardHacks.removeAll()
        
        for hack in event.hacks {
            let identifier = hack.identifier
            
            guard let hack = registry.hacks[identifier] else {
                continue
            }
            
            self.keyboardHacks.append(hack)
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
        var keyCode = NoctilucaPluginKit.LinuxKeycode(rawValue: UInt16(event.keyCode))
        
        for hack in self.keyboardHacks.filter({ $0.evaluate(keyCode) }) {
            let decision = switch event.eventType {
            case .keyDown:
                await hack.onKeyDown(keyCode)
            case .keyUp:
                await hack.onKeyUp(keyCode)
            default:
                await hack.onKeyDown(keyCode)
            }
            
            if case .modify(let modified) = decision {
                keyCode = modified
            } else if case .stop = decision {
                break
            }
        }
        
        guard let carbonKeyCode = LinuxKeycode(rawValue: UInt16(keyCode.rawValue)).toCarbonKeycode else {
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
        eventInjector.post(mouseMoveEvent: mouseMoveEvent)
    }
    
    override func handleStreamClose() {
        eventInjector.resetKeyboardState()
    }
    
    override func handleStreamError(error: (any Error)) {
        eventInjector.resetKeyboardState()
    }
}

fileprivate extension KeyboardHackPluginV1 {
    func evaluate(_ keyCode: NoctilucaPluginKit.LinuxKeycode) -> Bool {
        return type(of: self).desiredKeyEvents.contains(keyCode)
    }
}
