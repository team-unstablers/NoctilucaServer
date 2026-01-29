//
//  HIDIOGCKeyboard.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/18/25.
//

import Foundation

import Combine
import GameController

#if os(macOS)
import Cocoa
import CoreGraphics
#else
import UIKit
#endif


import SiriusKitClient

extension HIDIOVirtualDeviceIdentifier {
    /// GameController.framework를 사용한 마우스 가상 디바이스.
    static let gcMouse = Self(rawValue: UUID(uuidString: "D2DF5CDE-ED85-4CB3-9774-6CAE7B6C1D77")!)
}


// TODO: HIDIOGCMouseHub 만들기

/// # HIDIOGCMouse
/// - macOS / iOS GameController.framework를 사용해 마우스 입력을 처리합니다.
///
/// ## 플랫폼별 동작 (macOS)
/// - 이 장치가 HIDIOController에 연결되어 있는 동안, 마우스 커서는 숨겨지고, 중앙에 고정됩니다.
///
/// ## 플랫폼별 동작 (iOS, iPadOS, tvOS)
/// - 이 장치가 HIDIOController에 연결되어 있는 동안, 윈도우의 루트 뷰 컨트롤러에 커서 락이 걸립니다. (= 마우스 커서가 숨겨지고, 중앙에 고정됩니다)
///
///
class HIDIOGCMouse: HIDIOLockableVirtualDevice {
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
    static let identifier: HIDIOVirtualDeviceIdentifier = .gcMouse
    
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
    private var isHardwareConnected: Bool = false
    
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
                self?.isHardwareConnected = true
                self?.controller?.pointerInputRouter?.updateHardwareMouseConnected(true)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .GCMouseDidDisconnect)
            .compactMap { $0.object as? GCMouse }
            .sink { [weak self] mouse in
                self?.logger.debug("GCMouse did disconnect: \(mouse)")
                self?.isHardwareConnected = false
                self?.controller?.pointerInputRouter?.updateHardwareMouseConnected(false)
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
            let delta = CGPoint(x: CGFloat(deltaX), y: CGFloat(-deltaY))

            if let router = self?.controller?.pointerInputRouter {
                router.moveMouseRelative(from: .hardware, by: delta)
            } else {
                controller.moveMouseRelative(to: delta)
            }
            
            self?.centerCursor()
        }
        
        func setupButtonHandler(button: GCControllerButtonInput, as buttonType: MouseButtonType) {
            button.preferredSystemGestureState = .alwaysReceive
            button.valueChangedHandler = { [weak self] button, value, pressed in
                guard let controller = self?.controller else {
                    return
                }
                
                self?.logger.debug("Mouse button changed: value=\(value), pressed=\(pressed)")
                
                if pressed {
                    if let router = self?.controller?.pointerInputRouter {
                        router.mouseButtonDown(from: .hardware, button: buttonType)
                    } else {
                        controller.mouseButtonDown(button: buttonType)
                    }
                } else {
                    if let router = self?.controller?.pointerInputRouter {
                        router.mouseButtonUp(from: .hardware, button: buttonType)
                    } else {
                        controller.mouseButtonUp(button: buttonType)
                    }
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
            
#if os(macOS)
            /// TODO: 이거 화면 회전에 대응한 값이 오지 않음!!!
            let delta = CGPoint(x: CGFloat(xValue), y: CGFloat(-yValue))
#else
            /// TODO: 이거 화면 회전에 대응한 값이 오지 않음!!!
            let delta = CGPoint(x: CGFloat(yValue), y: CGFloat(-xValue))
#endif
            if let router = self?.controller?.pointerInputRouter {
                router.mouseWheel(from: .hardware, delta: delta)
            } else {
                controller.mouseWheel(delta: delta)
            }
        }
    }
    
    fileprivate func destroyMouseInputHandler() {
        self.mouse?.mouseInput?.mouseMovedHandler = nil
        
        self.mouse?.mouseInput?.leftButton.valueChangedHandler = nil
        self.mouse?.mouseInput?.rightButton?.valueChangedHandler = nil
        
        self.mouse?.mouseInput?.scroll.valueChangedHandler = nil
    }
    
    func connect(to controller: HIDIOController) {
        self.controller = controller
        controller.pointerInputRouter?.updateHardwareMouseConnected(isHardwareConnected)
    }
    
    func disconnect() {
        self.controller = nil
    }
    
    func lock() throws {
        self.setupMouseInputHandler()
        
        DispatchQueue.main.async {
            self.hideCursor()
        }
    }
    
    func unlock() throws {
        self.destroyMouseInputHandler()
        
        DispatchQueue.main.async {
            self.showCursor()
        }
    }
}

#if os(macOS)
fileprivate extension HIDIOGCMouse {
    /// 이 윈도우가 속한 디스플레이를 반환합니다.
    func currentDisplayID() -> CGDirectDisplayID? {
        if let screen = NSApp.keyWindow?.screen {
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
            return displayID
        }
        
        return nil
    }
    
    func hideCursor() {
        guard let displayID = currentDisplayID() else {
            return
        }
        
        // FIXME: 근데, 이렇게 했는데 창이 다른 디스플레이로 이동하면 어떻게 되는거야?
        CGDisplayHideCursor(displayID)
    }
    
    func showCursor() {
        guard let displayID = currentDisplayID() else {
            return
        }
        
        // FIXME: 근데, 이렇게 했는데 창이 다른 디스플레이로 이동하면 어떻게 되는거야?
        CGDisplayShowCursor(displayID)
    }
    
    func centerCursor() {
        guard let keyWindow = NSApp.keyWindow,
              let screen = keyWindow.screen
        else {
            return
        }
        
        
        // keyWindow의 중앙
        let center = NSPoint(
            x: keyWindow.frame.origin.x + (keyWindow.frame.size.width / 2),
            y: screen.frame.height - (keyWindow.frame.origin.y + (keyWindow.frame.size.height / 2))
        )
        
        logger.debug("Centering cursor to: \(center)")
        
        CGWarpMouseCursorPosition(center)
    }
}
#else
fileprivate extension HIDIOGCMouse {
    func rootViewController() -> RootViewController? {
        // FIXME: multi window (multi scene)에서 제대로 동작하는지?
        guard let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.rootViewController is RootViewController }),
              let rootViewController = window.rootViewController as? RootViewController
        else {
            return nil
        }
        
        return rootViewController
    }
    
    func hideCursor() {
        guard let rootViewController = self.rootViewController() else {
            return
        }
        
        rootViewController.isPointerLocked = true
    }
    
    func showCursor() {
        guard let rootViewController = self.rootViewController() else {
            return
        }
        
        rootViewController.isPointerLocked = false
    }
    
    func centerCursor() {
        // iOS는 rootViewController에서 isPointerLocked만 설정해두면 됨
    }
}
#endif
