//
//  EventInjector.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/11/25.
//

import Foundation

import Carbon

import SiriusKit

extension EventInjector {
    func post(keyEvent event: KeyboardEvent) {
        switch event.eventType {
        case .down:
            postKeyDown(Int(event.keyCode))
        case .up:
            postKeyUp(Int(event.keyCode))
        default:
            break
        }
    }
    
    func postKeyDown(_ keyCode: Int) {
        enqueue { [weak self] in
            self?.handleKeyDown(keyCode)
        }
    }
    
    func postKeyUp(_ keyCode: Int) {
        enqueue { [weak self] in
            self?.handleKeyUp(keyCode)
        }
    }

    func handleKeyDown(_ keyCode: Int) {
        if keyDownState.contains(keyCode) {
            return
        }
        
        keyDownState.insert(keyCode)
        postKeyEvent(keyCode: keyCode, isDown: true, isRepeat: false)

        guard isRepeatableKey(keyCode) else {
            return
        }
        
        repeatableKeysInOrder.removeAll(where: { $0 == keyCode })
        repeatableKeysInOrder.append(keyCode)
        repeatKey = keyCode
        refreshKeyRepeatSettings()
        restartRepeatTimerIfNeeded()
    }
    
    func handleKeyUp(_ keyCode: Int) {
        let wasDown = keyDownState.contains(keyCode)
        if wasDown {
            keyDownState.remove(keyCode)
        }
        
        postKeyEvent(keyCode: keyCode, isDown: false, isRepeat: false)

        guard isRepeatableKey(keyCode) else {
            return
        }
        
        repeatableKeysInOrder.removeAll(where: { $0 == keyCode })

        if repeatKey == keyCode {
            if let nextKey = repeatableKeysInOrder.last {
                repeatKey = nextKey
                refreshKeyRepeatSettings()
                restartRepeatTimerIfNeeded()
            } else {
                repeatKey = nil
                stopRepeatTimer()
            }
        }
    }
    
    func restartRepeatTimerIfNeeded() {
        stopRepeatTimer()
        
        guard isRepeatEnabled(), let repeatKey = repeatKey, keyDownState.contains(repeatKey) else {
            return
        }
        
        let timer = DispatchSource.makeTimerSource(queue: serialQueue)
        let delay = dispatchInterval(for: repeatDelay)
        let interval = dispatchInterval(for: repeatInterval)
        
        timer.schedule(deadline: .now() + delay, repeating: interval)
        timer.setEventHandler { [weak self] in
            self?.handleRepeatTick()
        }
        timer.resume()
        
        repeatTimer = timer
    }
    
    func handleRepeatTick() {
        guard let repeatKey = repeatKey,
              keyDownState.contains(repeatKey),
              isRepeatEnabled()
        else {
            stopRepeatTimer()
            return
        }
        
        postKeyEvent(keyCode: repeatKey, isDown: true, isRepeat: true)
    }
    
    func isRepeatableKey(_ keyCode: Int) -> Bool {
        switch keyCode {
        case kVK_Shift,
             kVK_RightShift,
             kVK_Control,
             kVK_RightControl,
             kVK_Option,
             kVK_RightOption,
             kVK_Command,
             kVK_RightCommand,
             kVK_Function,
             kVK_CapsLock:
            return false
        default:
            return true
        }
    }
}
