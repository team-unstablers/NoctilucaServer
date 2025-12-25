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

// TODO: HIDIOGCMouseHub 만들기
class HIDIOGCMouse: HIDIOVirtualDevice {
    private static var _shared: HIDIOGCMouse? = nil
    
    static func shared() -> HIDIOGCMouse? {
        if _shared == nil {
            let shared = HIDIOGCMouse()
            shared.setup()
            
            _shared = shared
        }
        
        return _shared
    }
    
    static let kind: HIDIOVirtualDeviceKind = .mouse
    
    private let logger = NoctilucaLogger(category: "HIDIOGCMouse")
    
    private var cancellables: Set<AnyCancellable> = []

    private var mouse: GCMouse? {
        willSet {
            if newValue == nil {
                self.destroyMouseInputHandler()
            }
        }
        didSet {
            if mouse != nil {
                self.setupMouseInputHandler()
            }
        }
    }
    
    private var controller: HIDIOController?

    init() {
    }
    
    deinit {
        self.disconnect()
    }

    fileprivate func setup() {
        NotificationCenter.default.publisher(for: .GCMouseDidConnect)
            .compactMap { $0.object as? GCMouse }
            .sink { [weak self] mouse in
                self?.logger.debug("GCMouse did connect: \(mouse)")
                
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .GCMouseDidDisconnect)
            .compactMap { $0.object as? GCMouse }
            .sink { [weak self] mouse in
                self?.logger.debug("GCMouse did disconnect: \(mouse)")
            }
            .store(in: &cancellables)
 
        
        NotificationCenter.default.publisher(for: .GCMouseDidBecomeCurrent)
            .compactMap { $0.object as? GCMouse }
            .sink { [weak self] mouse in
                self?.logger.debug("GCMouse mouse did become current: \(mouse)")
                self?.mouse = mouse
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .GCMouseDidStopBeingCurrent)
            .compactMap { $0.object as? GCMouse }
            .sink { [weak self] mouse in
                self?.logger.debug("GCMouse mouse did stop being current: \(mouse)")
                self?.mouse = nil
            }
            .store(in: &cancellables)
    }
    
    fileprivate func setupMouseInputHandler() {
        guard self.controller != nil else {
            return
        }
        
        guard let mouseInput = self.mouse?.mouseInput else {
            return
        }
        
        mouseInput.mouseMovedHandler = { [weak self] mouse, deltaX, deltaY in
            guard let controller = self?.controller else {
                return
            }
            
            self?.logger.debug("Mouse moved: deltaX=\(deltaX), deltaY=\(deltaY)")

            let position = CGPoint(x: CGFloat(deltaX), y: CGFloat(-deltaY))
            controller.moveMouseRelative(to: position)
        }
        
        func setupButtonHandler(button: GCControllerButtonInput, as buttonType: MouseButtonType) {
            button.valueChangedHandler = { [weak self] button, value, pressed in
                guard let controller = self?.controller else {
                    return
                }
                
                self?.logger.debug("Mouse button changed: value=\(value), pressed=\(pressed)")
                
                if pressed {
                    controller.mouseButtonDown(button: buttonType)
                } else {
                    controller.mouseButtonUp(button: buttonType)
                }
            }
        }
        
        setupButtonHandler(button: mouseInput.leftButton, as: .left)
        
        if let rightButton = mouseInput.rightButton {
            setupButtonHandler(button: rightButton, as: .right)
        }
        
        mouseInput.scroll.valueChangedHandler = { [weak self] wheel, xValue, yValue in
            guard let controller = self?.controller else {
                return
            }
            
            self?.logger.debug("Mouse wheel changed: xValue=\(xValue), yValue=\(yValue)")
            
            let delta = CGPoint(x: CGFloat(xValue), y: CGFloat(-yValue))
            controller.mouseWheel(delta: delta)
        }
    }
    
    fileprivate func destroyMouseInputHandler() {
        self.mouse?.mouseInput?.mouseMovedHandler = nil
    }
    
    func connect(to controller: HIDIOController) {
        self.controller = controller
        self.setupMouseInputHandler()
    }
    
    func disconnect() {
        self.controller = nil
        self.destroyMouseInputHandler()
    }
}
