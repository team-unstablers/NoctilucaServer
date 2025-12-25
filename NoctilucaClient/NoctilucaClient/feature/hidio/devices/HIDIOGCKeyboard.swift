//
//  HIDIOGCKeyboard.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/18/25.
//

import Foundation

import Combine
import GameController

import SiriusKitClient

class HIDIOGCKeyboard: HIDIOVirtualDevice {
    private static var _shared: HIDIOGCKeyboard? = nil
    
    static func shared() -> HIDIOGCKeyboard? {
        if _shared == nil {
            let shared = HIDIOGCKeyboard()
            shared.setup()
            
            _shared = shared
        }
        
        return _shared
    }
    
    static let kind: HIDIOVirtualDeviceKind = .keyboard
    
    private var cancellables: Set<AnyCancellable> = []

    private var keyboard: GCKeyboard? {
        willSet {
            if newValue == nil {
                self.destroyKeyboardInputHandler()
            }
        }
        didSet {
            if keyboard != nil {
                self.setupKeyboardInputHandler()
            }
        }
    }
    
    private var controller: HIDIOController?

    init() {

    }
    
    deinit {
        self.destroyKeyboardInputHandler()
        self.disconnect()
    }

    fileprivate func setup() {
        NotificationCenter.default.publisher(for: .GCKeyboardDidConnect)
            .compactMap { $0.object as? GCKeyboard }
            .sink { [weak self] keyboard in
                self?.keyboard = keyboard
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .GCKeyboardDidDisconnect)
            .compactMap { $0.object as? GCKeyboard }
            .sink { [weak self] keyboard in
                self?.keyboard = nil
            }
            .store(in: &cancellables)
    }

    
    fileprivate func setupKeyboardInputHandler() {
        guard self.controller != nil else {
            return
        }
        
        self.keyboard?.keyboardInput?.keyChangedHandler = { [weak self] keyboard, key, keyCode, pressed in
            guard let controller = self?.controller else {
                return
            }
            
            let keyCode = LinuxKeycode.from(gameController: keyCode)
            
            if pressed {
                controller.keyDown(keyCode: keyCode)
            } else {
                controller.keyUp(keyCode: keyCode)
            }
        }
    }
    
    fileprivate func destroyKeyboardInputHandler() {
        self.keyboard?.keyboardInput?.keyChangedHandler = nil
    }
    
    func connect(to controller: HIDIOController) {
        self.controller = controller
        self.setupKeyboardInputHandler()
    }
    
    func disconnect() {
        self.controller = nil
        self.destroyKeyboardInputHandler()
    }
}
