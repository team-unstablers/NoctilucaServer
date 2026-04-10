//
//  HIDIOGCKeyboard.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 12/18/25.
//

import Foundation

import Combine
import GameController
import Atomics

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
@MainActor
final class HIDIOGCMouse: HIDIOVirtualDevice {
    nonisolated(unsafe) private static var _shared: HIDIOGCMouse? = nil

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
    
    var localIdentifier: String? { nil }

    private var cancellables: Set<AnyCancellable> = []
    
    private weak var controller: HIDIOController?

#if os(macOS)
    weak var window: NSWindow?
#endif

#if os(macOS)
    private static let recenterIntervalNanoseconds: UInt64 = 8_000_000
    nonisolated private let shouldRecenterCursor = ManagedAtomic<Bool>(false)
    private var recenterTask: Task<Void, Never>?
#endif

    init() {
    }

    deinit {
        // HIDIOGCMouse 는 @MainActor 이지만 deinit 은 nonisolated.
        // disconnect() 는 MainActor-isolated 이므로 직접 호출할 수 없다.
        // 정상 경로에서는 상위가 disconnect() 를 호출한다는 전제.
    }

    fileprivate func setup() {
        NotificationCenter.default.publisher(for: .GCMouseDidConnect)
            .compactMap { $0.object as? GCMouse }
            .sink { [weak self] mouse in
                Task { @MainActor [weak self] in
                    self?.logger.debug("GCMouse did connect: \(mouse)")
                    self?.updateHandler()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .GCMouseDidDisconnect)
            .compactMap { $0.object as? GCMouse }
            .sink { [weak self] mouse in
                Task { @MainActor [weak self] in
                    self?.logger.debug("GCMouse did disconnect: \(mouse)")
                    self?.updateHandler()
                }
            }
            .store(in: &cancellables)


        NotificationCenter.default.publisher(for: .GCMouseDidBecomeCurrent)
            .compactMap { $0.object as? GCMouse }
            .sink { [weak self] mouse in
                Task { @MainActor [weak self] in
                    self?.logger.debug("GCMouse mouse did become current: \(mouse)")
                    self?.updateHandler()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .GCMouseDidStopBeingCurrent)
            .compactMap { $0.object as? GCMouse }
            .sink { [weak self] mouse in
                Task { @MainActor [weak self] in
                    self?.logger.debug("GCMouse mouse did stop being current: \(mouse)")
                    self?.updateHandler()
                }
            }
            .store(in: &cancellables)

        if let currentMouse = GCMouse.current {
            self.logger.debug("Found existing current GCMouse: \(currentMouse)")
        } else if let firstMouse = GCMouse.mice().first {
            self.logger.debug("Found existing GCMouse (not current): \(firstMouse)")
        }

        self.updateHandler()
    }
    
    fileprivate func updateHandler() {
        if self.controller != nil {
            self.setupMouseInputHandler()
#if os(macOS)
            self.startRecenterLoopIfNeeded()
#endif
        } else {
            self.destroyMouseInputHandler()
#if os(macOS)
            self.stopRecenterLoop()
#endif
        }
    }
    
    fileprivate func setupMouseInputHandler() {
        guard self.controller != nil else {
            return
        }

        for mouse in GCMouse.mice() {
            guard let mouseInput = mouse.mouseInput else {
                return
            }

            // GameController 콜백은 기본적으로 main queue 에서 delivery 되지만
            // 문서상 isolation 보장이 없으므로 Task { @MainActor } 로 명시 진입한다.
            mouseInput.mouseMovedHandler = { [weak self] mouse, deltaX, deltaY in
                Task { @MainActor [weak self] in
                    guard let controller = self?.controller else {
                        return
                    }

                    let delta = CGPoint(x: CGFloat(deltaX), y: CGFloat(-deltaY))
                    controller.moveMouseRelative(to: delta)
                    self?.requestCursorRecenter()
                }
            }

            func setupButtonHandler(button: GCControllerButtonInput, as buttonType: MouseButtonType) {
                button.preferredSystemGestureState = .alwaysReceive
                button.valueChangedHandler = { [weak self] button, value, pressed in
                    Task { @MainActor [weak self] in
                        guard let controller = self?.controller else {
                            return
                        }

                        if pressed {
                            controller.mouseButtonDown(button: buttonType)
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
                Task { @MainActor [weak self] in
                    guard let controller = self?.controller else {
                        return
                    }

                    self?.logger.debug("Mouse wheel changed: xValue=\(xValue), yValue=\(yValue)")

#if os(macOS)
                    let multiplier: Float = 16.0
                    /// TODO: 이거 화면 회전에 대응한 값이 오지 않음!!!
                    let delta = CGPoint(x: CGFloat(xValue * multiplier), y: CGFloat(yValue * multiplier))
#else
                    /// TODO: 이거 화면 회전에 대응한 값이 오지 않음!!!
                    let delta = CGPoint(x: CGFloat(yValue), y: CGFloat(-xValue))
#endif
                    controller.mouseWheel(delta: delta)
                }
            }
        }
    }
    
    fileprivate func destroyMouseInputHandler() {
        for mouse in GCMouse.mice() {
            mouse.mouseInput?.mouseMovedHandler = nil
            
            mouse.mouseInput?.leftButton.valueChangedHandler = nil
            mouse.mouseInput?.rightButton?.valueChangedHandler = nil
            
            mouse.mouseInput?.scroll.valueChangedHandler = nil
        }
    }
    
    func connect(to controller: HIDIOController) {
        self.controller = controller
        self.setupMouseInputHandler()
#if os(macOS)
        self.hideCursor()
        self.startRecenterLoopIfNeeded()
#endif
    }

    func disconnect() {
        self.controller = nil
        self.destroyMouseInputHandler()
#if os(macOS)
        self.showCursor()
        self.stopRecenterLoop()
#endif
    }

    private func requestCursorRecenter() {
#if os(macOS)
        shouldRecenterCursor.store(true, ordering: .releasing)
#endif
    }

#if os(macOS)
    private func startRecenterLoopIfNeeded() {
        guard recenterTask == nil else {
            return
        }

        logger.debug("Starting cursor recenter loop (8ms)")
        recenterTask = Task.detached { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.recenterIntervalNanoseconds)
                guard let self else {
                    return
                }

                let shouldRecenter = self.shouldRecenterCursor.exchange(false, ordering: .acquiring)
                guard shouldRecenter else {
                    continue
                }

                await MainActor.run { [weak self] in
                    self?.centerCursor()
                }
            }
        }
    }

    private func stopRecenterLoop() {
        guard recenterTask != nil else {
            return
        }

        logger.debug("Stopping cursor recenter loop")
        recenterTask?.cancel()
        recenterTask = nil
        shouldRecenterCursor.store(false, ordering: .relaxed)
    }
#endif
}

#if os(macOS)
fileprivate extension HIDIOGCMouse {
    /// 이 윈도우가 속한 디스플레이를 반환합니다.
    func currentDisplayID() -> CGDirectDisplayID? {
        if let screen = self.window?.screen {
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! CGDirectDisplayID
            return displayID
        }

        return CGMainDisplayID()
    }
    
    @MainActor
    func hideCursor() {
        guard let displayID = currentDisplayID() else {
            return
        }
        
        // FIXME: 근데, 이렇게 했는데 창이 다른 디스플레이로 이동하면 어떻게 되는거야?
        CGDisplayHideCursor(displayID)
    }
    
    @MainActor
    func showCursor() {
        guard let displayID = currentDisplayID() else {
            return
        }
        
        // FIXME: 근데, 이렇게 했는데 창이 다른 디스플레이로 이동하면 어떻게 되는거야?
        CGDisplayShowCursor(displayID)
    }
    
    @MainActor
    func centerCursor() {
        guard let window = self.window,
              window.screen != nil
        else {
            return
        }

        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? 0
        let center = NSPoint(
            x: window.frame.midX,
            y: mainScreenHeight - window.frame.midY
        )

        CGWarpMouseCursorPosition(center)
    }
}
#else
fileprivate extension HIDIOGCMouse {
    func rootViewController() -> RootViewController? {
        // FIXME: multi window (multi scene)에서 제대로 동작하는지?
        let scenes = UIApplication.shared.connectedScenes
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene ?? scenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: { $0.rootViewController is RootViewController }),
              let rootViewController = window.rootViewController as? RootViewController
        else {
            return nil
        }
        
        return rootViewController
    }
    
    @MainActor
    func hideCursor() {
        guard let rootViewController = self.rootViewController() else {
            return
        }
        
        rootViewController.isPointerLocked = true
    }
    
    @MainActor
    func showCursor() {
        guard let rootViewController = self.rootViewController() else {
            return
        }
        
        rootViewController.isPointerLocked = false
    }
    
    @MainActor
    func centerCursor() {
        // iOS는 rootViewController에서 isPointerLocked만 설정해두면 됨
    }
}
#endif
