//
//  EventInjector.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/11/25.
//

import Foundation

import Carbon
import CoreGraphics

import SiriusKit

extension EventInjector {
    func post(keyEvent event: KeyboardEvent) {
        switch event.eventType {
        case .down:
            performKeyDown(Int(event.keyCode), modifiers: Int(event.modifiers))
        case .up:
            performKeyUp(Int(event.keyCode), modifiers: Int(event.modifiers))
        default:
            break
        }
    }
    
    internal func performKeyDown(_ keyCode: Int, modifiers: Int) {
        keyDownState.insert(keyCode)
        
        guard let cgEvent = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: CGKeyCode(keyCode),
            keyDown: true
        )
        else {
            return
        }
        
        
        cgEvent.sanitizeModifierFlags(with: keyDownState)
        cgEvent.post(tap: .cgSessionEventTap)
    }
    
    internal func performKeyUp(_ keyCode: Int, modifiers: Int) {
        keyDownState.remove(keyCode)

        guard let cgEvent = CGEvent(
            keyboardEventSource: eventSource,
            virtualKey: CGKeyCode(keyCode),
            keyDown: false
        )
        else {
            return
        }
        
        cgEvent.sanitizeModifierFlags(with: keyDownState)
        cgEvent.post(tap: .cgSessionEventTap)
    }
}

