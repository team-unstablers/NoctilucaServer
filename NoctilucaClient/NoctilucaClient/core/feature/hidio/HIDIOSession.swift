//
//  HIDIOSession.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/5/26.
//

import Foundation
import Combine

enum HIDIOSessionMode: Equatable, Hashable {
    /// 공유 모드 (Shared Mode)
    ///
    /// ## macOS
    /// - 다른 애플리케이션과 HID 디바이스를 공유하여 사용할 수 있습니다.
    /// - 다른 애플리케이션과 빠르게 오가며 HID 입력을 사용할 수 있습니다.
    /// - 포인팅 디바이스는 AppKit(NSView) / NSEvent 기반의 입력 이벤트로 수신됩니다.
    ///
    /// ## iOS / iPadOS
    /// - 다른 애플리케이션과 HID 디바이스를 공유하여 사용할 수 있습니다.
    /// - 다른 애플리케이션과 빠르게 오가며 HID 입력을 사용할 수 있습니다.
    /// - 포인팅 디바이스는 UIKit(UIView) 기반의 입력 이벤트로 수신됩니다. (see HIDIOUIKitMouseView)
    ///
    case shared
    
    /// 독점 모드 (Exclusive Mode)
    ///
    /// ## macOS
    /// - HID 디바이스 (키보드, 마우스)에 잠금을 걸고, 독점적으로 사용합니다.
    /// - 특정한 키스트로크 조합으로 잠금이 해제되기 전 까지는 다른 애플리케이션으로 전환하거나, 다른 애플리케이션에서 HID 입력을 받을 수 없습니다.
    ///
    /// ## iOS / iPadOS
    /// - 이 모드는 iOS / iPadOS에서 사용할 수 없습니다.
    @available(iOS, unavailable)
    case exclusive
    
    
    /// 제한된 독점 모드 (Limited Exclusive Mode)
    ///
    /// ## macOS
    /// - 이 모드는 macOS에서 사용할 수 없습니다.
    ///
    /// ## iPadOS
    /// - 포인팅 디바이스에 한해 독점 사용을 시도합니다.
    /// - root level의 UIViewController의 isPointerLocked를 true로 설정하여, FPS 게임처럼 마우스를 독점합니다. 포인터는 화면 중앙에 고정되며, 입력 디바이스는 GCMouse (relative)로 강제 전환됩니다.
    ///
    /// ### Note
    /// - 포인터 락은 전체 화면 (Maximized) 모드에서만 동작합니다. 전체 화면 모드가 아닌 상태에서는 포인터 락이 적용되지 않으므로, 전체 화면이 아니게 되었을 때는 공유 모드로 자동 전환이 이루어져야 합니다.
    /// - 포인터 락은 키보드의 `escape` 키를 누르면 해제됩니다. 따라서, esc 키 핸들링 시 포인터 락을 다시 걸도록 하는 전략을 취해야 할 수도 있습니다.
    ///
    /// ## iOS
    /// - 이 모드는 iOS에서 제대로 동작하지 않을 수 있습니다.
    @available(macOS, unavailable)
    case limitedExclusive
}

enum HIDIOSessionModeSwitchReason: Equatable, Hashable {
    /// 사용자 동작 (키스트로크)로 인해 전환되었습니다.
    case userInitiated
    
    /// 현재 모드가 지원되지 않아 자동으로 전환되었습니다. (UI 모드 전환 등)
    case unsupportedMode
    
    /// 기타 이유로 인해 전환되었습니다.
    case other(description: String)
}

enum HIDIOSessionState: Equatable, Hashable {
    case inactive
    case active
}

protocol HIDIOSessionDelegate: AnyObject {
    /// 세션 상태가 변경되었음을 알립니다.
    func hidioSession(_ session: HIDIOSession, didChangeState state: HIDIOSessionState)
    
    /// 세션 모드가 변경되었음을 알립니다.
    func hidioSession(_ session: HIDIOSession, didSwitchMode mode: HIDIOSessionMode, reason: HIDIOSessionModeSwitchReason)
}

class HIDIOSession: ObservableObject {
    protocol Driver {
        init(_ session: HIDIOSession)
        
        var currentKeyboard: HIDIOVirtualDevice? { get }
        var currentMouse: HIDIOVirtualDevice? { get }
        
        /// 세션을 시작합니다.
        func startSession() throws -> HIDIOSessionMode
        /// 세션을 종료합니다.
        func stopSession()
        
        /// 세션을 활성화합니다.
        /// 이 이벤트는 원격 세션 창이 포커스될 때 호출됩니다.
        func activateSession()
        /// 세션을 비활성화합니다.
        /// 이 이벤트는 원격 세션 창이 포커스를 잃을 때 호출됩니다.
        func deactivateSession()
        
        /// 입력 모드를 전환합니다.
        func switchMode(to mode: HIDIOSessionMode, reason: HIDIOSessionModeSwitchReason) throws
        /// 전환 가능한 모드 집합을 반환합니다.
        func switchableModes() -> Set<HIDIOSessionMode>
    }
    
    @Published
    private(set) var mode: HIDIOSessionMode
    private(set) var controller: HIDIOController
    
    private var driver: Driver!
    
#if os(iOS)
    var defaultSubMouse: HIDIOVirtualDevice {
        (driver as! IOSDriver).defaultSubMouse
    }
#endif
    
    var currentMouse: HIDIOVirtualDevice? {
        driver.currentMouse
    }
    
    var currentKeyboard: HIDIOVirtualDevice? {
        driver.currentKeyboard
    }
    
    /// NOTE: delegate 호출은 Driver에서 담당합니다. 이 클래스에서는 호출하지 않습니다.
    weak var delegate: HIDIOSessionDelegate?
    
    init(_ controller: HIDIOController) {
        self.mode = .shared
        self.controller = controller
        
#if os(macOS)
        self.driver = MacOSDriver(self)
#elseif os(iOS)
        self.driver = IOSDriver(self)
#endif
    }
    
    /// HIDIO 입력 리디렉션 세션을 시작합니다.
    func startSession() throws {
        let initialMode = try driver.startSession()
        self.mode = initialMode
    }
    /// HIDIO 입력 리디렉션 세션을 종료합니다.
    func stopSession()  {
        driver.stopSession()
    }
    
    /// HIDIO 입력 리디렉션 세션을 활성화합니다.
    func activateSession() {
        driver.activateSession()
    }
    
    /// HIDIO 입력 리디렉션 세션을 비활성화합니다.
    /// Note:
    ///  - 이 메소드는 원격 세션 창이 포커스를 잃을 때 호출되어야 합니다.
    ///  - 이 메소드는 사용자 경험을 위해 mode가 `.shared`인 경우, 마우스에 대한 입력 잠금을 해제하지 않습니다.
    func deactivateSession() {
        driver.deactivateSession()
    }
    
    /// 입력 모드를 전환합니다.
    func switchMode(to mode: HIDIOSessionMode, reason: HIDIOSessionModeSwitchReason) throws {
        if self.mode == mode {
            return
        }
        
        try driver.switchMode(to: mode, reason: reason)
        self.mode = mode
    }
    
    /// 전환 가능한 모드 집합을 반환합니다.
    func switchableModes() -> Set<HIDIOSessionMode> {
        return driver.switchableModes()
    }
}
