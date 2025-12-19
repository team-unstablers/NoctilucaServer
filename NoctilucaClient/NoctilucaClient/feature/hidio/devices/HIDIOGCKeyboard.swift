//
//  HIDIOGCKeyboard.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/18/25.
//

import Foundation

import GameController

import SiriusKitClient

@objc
class HIDIOGCKeyboardLifecycleListener: NSObject {
    @objc
    public func keyboardConnected() {
    }
    
    @objc
    public func keyboardDisconnected() {
    }
}

class HIDIOGCKeyboard: HIDIOVirtualDevice {
    static let lifecycleListener = HIDIOGCKeyboardLifecycleListener()
    
    static func coalesced() -> HIDIOGCKeyboard? {
        guard let gcKeyboard = GCKeyboard.coalesced else {
            return nil
        }
        
        return HIDIOGCKeyboard(gcKeyboard)
    }
    
    /// 라이프사이클 리스너를 등록한다.
    /// GCKeyboard는 Notification을 구독하지 않으면 사용할 수 없는 듯 하다
    static func registerLifecycleListener() {
        NotificationCenter.default.addObserver(
            lifecycleListener,
            selector: #selector(HIDIOGCKeyboardLifecycleListener.keyboardConnected),
            name: .GCKeyboardDidConnect,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            lifecycleListener,
            selector: #selector(HIDIOGCKeyboardLifecycleListener.keyboardDisconnected),
            name: .GCKeyboardDidDisconnect,
            object: nil
        )
    }
    
    static let kind: HIDIOVirtualDeviceKind = .keyboard

    private let keyboard: GCKeyboard
    private var keyboardInput: GCKeyboardInput
    
    private var controller: HIDIOController?
    
    deinit {
        self.disconnect()
    }
    
    init(_ keyboard: GCKeyboard) {
        self.keyboard = keyboard
        self.keyboardInput = keyboard.keyboardInput!
    }
    
    func connect(to controller: HIDIOController) {
        self.controller = controller
        
        self.keyboardInput.keyChangedHandler = { [weak self] keyboard, key, keyCode, pressed in
            // print(keyboard, key, keyCode, pressed)
            Task {
                let keyCode = LinuxKeycode.from(gameController: keyCode)
                try? await self?.controller?.keyDown(keyCode: keyCode)
            }
        }
    }
    
    func disconnect() {
        self.keyboardInput.keyChangedHandler = nil
    }
}
