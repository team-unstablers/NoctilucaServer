//
//  DesktopContextManager.swift
//  NoctilucaServer
//

import os

@preconcurrency import Foundation

import CoreGraphics
@preconcurrency import ApplicationServices // For AXUIElement
@preconcurrency import AppKit
import Combine

import SiriusKit

// MARK: - Core Types

let kAXWindowNumberAttribute = "AXWindowNumber"

typealias WindowID = CGWindowID

// MARK: - AX Helpers

/// AXUIElement에서 문자열 속성을 안전하게 읽는다. 실패 시 nil.
private func axStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return nil
    }
    return value as? String
}

/// AXUIElement에서 AXUIElement 타입 속성을 안전하게 읽는다. 실패 시 nil.
private func axElementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
        return nil
    }
    let ref = value!
    guard CFGetTypeID(ref) == AXUIElementGetTypeID() else {
        return nil
    }
    return (ref as! AXUIElement)
}

/// AXUIElement에서 Bool 속성을 안전하게 읽는다. 실패 / 타입 불일치 시 nil.
private func axBoolAttribute(_ element: AXUIElement, _ attribute: String) -> Bool? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let cf = value
    else {
        return nil
    }
    guard CFGetTypeID(cf) == CFBooleanGetTypeID() else {
        return nil
    }
    return CFBooleanGetValue((cf as! CFBoolean))
}

struct SkyLightWindowInfo: Sendable {
    let parentWindowId: CGWindowID?
    let tag: CGSWindowTag
}

/// SkyLight Window Query API를 통해 윈도우의 parent window ID를 조회한다.
/// 실패 시 nil.
private func getSkyLightWindowInfo(for windowID: CGWindowID) -> SkyLightWindowInfo? {
    guard let connection = SkyLightPrivate.SLSMainConnectionID?() else {
        return nil
    }
    guard let query = SkyLightPrivate.SLSWindowQueryWindows?(connection, [windowID] as CFArray, 1) else {
        return nil
    }
    guard let iterator = SkyLightPrivate.SLSWindowQueryResultCopyWindows?(query) else {
        return nil
    }
    
    _ = SkyLightPrivate.SLSWindowIteratorAdvance?(iterator)
    
    let rawTag = SkyLightPrivate.SLSWindowIteratorGetTags?(iterator) ?? 0
    let tag = CGSWindowTag(rawValue: rawTag)
    
    let parentID = SkyLightPrivate.SLSWindowIteratorGetParentID?(iterator)
    
    return SkyLightWindowInfo(parentWindowId: parentID, tag: tag)
}

/// AXRole/AXSubrole 조합을 WindowRole로 매핑
private func mapAXRoleToWindowRole(axRole: String?, axSubrole: String?) -> WindowRole {
    guard let axRole else { return .normal }

    switch axRole {
    case "AXWindow":
        switch axSubrole {
        case "AXDialog", "AXSheet", "AXSystemDialog":
            return .dialog
        case "AXStandardWindow", "AXFloatingWindow", nil:
            return .normal
        default:
            return .normal
        }
    case "AXMenu", "AXMenuBar":
        return .menu
    case "AXPopover":
        return .tooltip
    default:
        return .normal
    }
}

/// WindowInfo 보강용 AX 속성 묶음
private struct AXWindowAttributes {
    let axClassName: String?
    let axRole: String?
    let axSubrole: String?

    /// 셋 다 nil 이면 borderless / decoration 없는 윈도우로 본다.
    let hasCloseButton: Bool
    let hasMinimizeButton: Bool
    let hasZoomButton: Bool

    /// 버튼이 존재하지 않으면 false. 존재하지만 disabled 인 경우만 false 가 의미를 가짐.
    let isMinimizeEnabled: Bool
    let isZoomEnabled: Bool

    let isMinimized: Bool
    let isFullscreenAX: Bool

    var windowRole: WindowRole {
        mapAXRoleToWindowRole(axRole: axRole, axSubrole: axSubrole)
    }

    /// 신호등 자체가 아예 없는 borderless 윈도우인지.
    var hasNoTitleBarButtons: Bool {
        !hasCloseButton && !hasMinimizeButton && !hasZoomButton
    }

    static let empty = AXWindowAttributes(
        axClassName: nil,
        axRole: nil,
        axSubrole: nil,
        hasCloseButton: false,
        hasMinimizeButton: false,
        hasZoomButton: false,
        isMinimizeEnabled: false,
        isZoomEnabled: false,
        isMinimized: false,
        isFullscreenAX: false
    )
}

/// AXUIElement로부터 WindowInfo 보강용 속성들을 일괄 읽는다.
private func readAXWindowAttributes(from element: AXUIElement) -> AXWindowAttributes {
    let axClassName = axStringAttribute(element, "AXClassName")
    let axRole = axStringAttribute(element, kAXRoleAttribute as String)
    let axSubrole = axStringAttribute(element, kAXSubroleAttribute as String)

    let closeButton = axElementAttribute(element, kAXCloseButtonAttribute as String)
    let minimizeButton = axElementAttribute(element, kAXMinimizeButtonAttribute as String)
    let zoomButton = axElementAttribute(element, kAXZoomButtonAttribute as String)

    let isMinimizeEnabled: Bool = {
        guard let minimizeButton else { return false }
        return axBoolAttribute(minimizeButton, kAXEnabledAttribute as String) ?? true
    }()
    let isZoomEnabled: Bool = {
        guard let zoomButton else { return false }
        return axBoolAttribute(zoomButton, kAXEnabledAttribute as String) ?? true
    }()

    let isMinimized = axBoolAttribute(element, kAXMinimizedAttribute as String) ?? false
    let isFullscreenAX = axBoolAttribute(element, "AXFullScreen") ?? false

    return AXWindowAttributes(
        axClassName: axClassName,
        axRole: axRole,
        axSubrole: axSubrole,
        hasCloseButton: closeButton != nil,
        hasMinimizeButton: minimizeButton != nil,
        hasZoomButton: zoomButton != nil,
        isMinimizeEnabled: isMinimizeEnabled,
        isZoomEnabled: isZoomEnabled,
        isMinimized: isMinimized,
        isFullscreenAX: isFullscreenAX
    )
}

// MARK: - WindowInfo signal derivation (CGSWindowTag + AX → Sirius flags/hints)

/// fetchWindowList 가 채울 hints / flags / metadata 묶음.
private struct WindowInfoSignalSet {
    var hints: WindowHint
    var flags: WindowInfoFlags
    var metadataExtras: [String: String]
}

/// AX 속성과 CGSWindowTag, CGWindowList 값들을 종합해 Sirius `WindowInfo` 의
/// hints / flags / metadata 를 산출한다.
///
/// 신호 우선순위:
///   - `noWindowDecoration` 은 AX 버튼 셋 다 nil (primary) OR CGSWindowTag 휴리스틱 (fallback).
///   - 그 외 플래그/힌트는 AX 와 tag 중 더 직접적인 쪽을 1차로 사용하고, 여건이 되면 cross-check.
private func deriveWindowInfoSignals(
    axAttrs: AXWindowAttributes,
    skyLightInfo: SkyLightWindowInfo,
    isFocused: Bool,
    isOnscreen: Bool,
    isVisible: Bool,
    layer: Int32
) -> WindowInfoSignalSet {
    let tag = skyLightInfo.tag

    // MARK: hints

    var hints: WindowHint = []
    // border-radius / 부분 투명은 macOS 윈도우 대부분에 해당. tag 에 명확한 inverse
    // 신호가 없어 보수적으로 항상 true 로 둔다.
    hints.insert(.hasTransparency)

    if !tag.contains(.disableShadow) {
        hints.insert(.hasShadow)
    }
    if tag.contains(.avoidsCapture) {
        hints.insert(.protectedContent)
    }
    if tag.contains(.attachesToMenuBar)
        || tag.contains(.mergesWithMenuBar)
        || tag.contains(.windowIsMagicMirror)
        || tag.contains(.desktopPicture)
    {
        hints.insert(.systemUI)
    }

    // MARK: flags

    var flags: WindowInfoFlags = []

    if isFocused {
        flags.insert(.isFocused)
    }
    if !isVisible || !isOnscreen || tag.contains(.hidden) {
        flags.insert(.isHidden)
    }
    if axAttrs.isMinimized {
        flags.insert(.isMinimized)
    }
    if axAttrs.isFullscreenAX || tag.contains(.fullScreen) {
        flags.insert(.isFullscreen)
    }

    // 신호등 자체가 없는 borderless 윈도우 판정.
    let noDecorationByAX = axAttrs.hasNoTitleBarButtons
    let noDecorationByTag =
        tag.contains(.attachedWindow)
        || tag.contains(.attachesToMenuBar)
        || tag.contains(.mergesWithMenuBar)
        || (tag.contains(.disableShadow)
            && (tag.contains(.ignoreForEvents)
                || tag.contains(.avoidsActivation)
                || tag.contains(.preventsActivation)))
    if noDecorationByAX || noDecorationByTag {
        flags.insert(.noWindowDecoration)
    }

    // 버튼이 존재하면서 disabled 인 경우만 cannot* 로 본다. 버튼 자체가 없는 케이스는
    // noWindowDecoration 으로 흡수되므로 따로 set 하지 않는다.
    if axAttrs.hasMinimizeButton && !axAttrs.isMinimizeEnabled {
        flags.insert(.cannotMinimize)
    }
    if axAttrs.hasZoomButton && !axAttrs.isZoomEnabled {
        flags.insert(.cannotMaximize)
    }
    if !tag.contains(.fullScreenCapable) && !tag.contains(.fullScreenTileCapable) {
        flags.insert(.cannotFullscreen)
    }

    // 레벨 / 플로팅: kCGNormalWindowLevel == 0. 양수는 floating/utility/popup,
    // 음수는 desktop 류.
    if tag.contains(.floatingWindow) || layer > 0 {
        flags.insert(.isTopmost)
    }
    if tag.contains(.desktopPicture) || layer < 0 {
        flags.insert(.isBottommost)
    }

    if tag.contains(.ignoreForExpose) {
        flags.insert(.skipWindowEntry)
    }

    // MARK: metadata

    let metadataExtras: [String: String] = [
        "app.noctiluca.server.x-cgs-tags": tag.debugDescription,
        "app.noctiluca.server.x-cgs-tags-raw": String(format: "0x%016llx", tag.rawValue),
    ]

    return WindowInfoSignalSet(
        hints: hints,
        flags: flags,
        metadataExtras: metadataExtras
    )
}

/*
/// winman.proto의 WindowInfo와 매핑되기 쉽도록 구조화
struct WindowInfo: Identifiable, Equatable, Hashable {
    typealias ID = CGWindowID // UInt32
    
    let id: ID
    let title: String
    let frame: CGRect
    let isVisible: Bool
    let isActive: Bool // 현재 포커스 된 윈도우인지
    
    // CGWindowList API 등을 통해 가져온 추가 메타데이터
    let layer: Int32
    let ownerPID: pid_t
}
 */

enum AppIdentifier: Hashable, CustomStringConvertible {
    case bundleID(String)
    case processID(pid_t)
    
    var description: String {
        switch self {
        case .bundleID(let id): return "Bundle(\(id))"
        case .processID(let pid): return "PID(\(pid))"
        }
    }
}

// MARK: - Errors

enum DesktopContextError: Error, LocalizedError {
    case accessibilityPermissionMissing
    case cannotCreateAXObserver(AXError)
    case windowNotFound(WindowID)
    case windowOwnerNotFound(WindowID)
    case appNotRunning
    case invalidWindowFrame
    case failedToSetFocusedWindow(AXError)
    case failedToPerformAction(String, AXError)
    case failedToUpdateWindowFrame(AXError)
    case failedToReadAttribute(String, AXError)
    case unsupportedOperation(String)

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            return "Accessibility permission is not granted"
        case .cannotCreateAXObserver(let error):
            return "Cannot create AXObserver: \(error)"
        case .windowNotFound(let id):
            return "Window not found: \(id)"
        case .windowOwnerNotFound(let id):
            return "Owner process not found for window: \(id)"
        case .appNotRunning:
            return "Application is not running"
        case .invalidWindowFrame:
            return "Invalid window frame"
        case .failedToSetFocusedWindow(let error):
            return "Failed to set focused window: \(error)"
        case .failedToPerformAction(let action, let error):
            return "Failed to perform action '\(action)': \(error)"
        case .failedToUpdateWindowFrame(let error):
            return "Failed to update window frame: \(error)"
        case .failedToReadAttribute(let attr, let error):
            return "Failed to read attribute '\(attr)': \(error)"
        case .unsupportedOperation(let op):
            return "Unsupported operation: \(op)"
        }
    }
}

// MARK: - Protocols

/// 특정 앱(AppSession)에서 발생하는 이벤트를 수신
@MainActor
protocol AppSessionDelegate: AnyObject {
    // Lifecycle
    func appSessionDidTerminate(_ session: AppSession)
    func appSession(_ session: AppSession, didEncounterError error: Error)
    
    // App Focus
    func appSessionDidBecomeActive(_ session: AppSession)
    func appSessionDidResignActive(_ session: AppSession)

    // Menu (accessibility.mdproto AccessibilityNode 기반)
    /// 앱의 메뉴바 서브트리에 변화가 감지되면 호출된다. 초기 구현은 전체 재스냅샷을 전달한다.
    /// Phase 4에서 diff 기반 세밀한 이벤트로 확장 예정.
    func appSession(_ session: AppSession, didUpdateMenuBar rootNode: AccessibilityNode)

    // Context Menu (popup): 메뉴바 산하가 아닌 우클릭 등으로 뜨는 transient popup 메뉴.
    // AccessibilityTreeUpdateEvent (.nodeAdded / .nodeRemoved) 로 클라에 직렬화될 예정.
    /// popup 메뉴가 호스트에서 열리면 호출된다. `tree.id` 가 곧 menuId 이며, 클라이언트가
    /// native NSMenu 로 미러링하기 위한 트리이다.
    func appSession(
        _ session: AppSession,
        didOpenContextMenu tree: AccessibilityNode,
        hostBounds: CGRect,
        triggerWindowID: WindowID?
    )

    /// popup 메뉴가 호스트 측에서 dismiss 되면 호출된다. AppMenuRegistry 역매핑으로 menuId 를
    /// 찾을 수 없는 경우(예: 미등록 element) 호출되지 않는다.
    func appSession(_ session: AppSession, didCloseContextMenu menuID: UUID)

    // Window Events (winman.proto의 Window...Event 메시지들과 대응)
    /// 윈도우가 생성되었거나, 감시 대상에 포함됨
    func appSession(_ session: AppSession, didDiscoverWindow window: WindowInfo)
    
    /// 윈도우 정보 변경 (이동, 리사이즈, 타이틀 변경 통합 - 최적화 위함)
    /// 개별 이벤트가 필요하면 didMove, didResize 등으로 분리 가능
    func appSession(_ session: AppSession, didUpdateWindow window: WindowInfo)
    
    /// 윈도우가 닫힘 (winman.proto: WindowClosedEvent)
    func appSession(_ session: AppSession, didCloseWindow windowID: WindowID)
    
    /// 앱 내에서 윈도우 포커스가 변경됨 (winman.proto: WindowFocusChangedEvent)
    func appSession(_ session: AppSession, didChangeWindowFocusTo windowID: WindowID?)
}

/// 시스템 전체(DesktopContextManager)에서 발생하는 이벤트를 수신
@MainActor
protocol DesktopContextManagerDelegate: AnyObject {
    /// 새로운 앱이 실행됨 (감시 시작 가능 시점)
    func desktopManager(_ manager: DesktopContextManager, didDetectAppLaunch app: NSRunningApplication)
    
    /// 앱이 종료됨
    func desktopManager(_ manager: DesktopContextManager, didDetectAppTermination pid: pid_t)
    
    /// 시스템 전체에서 포커스된 앱이 변경됨
    func desktopManager(_ manager: DesktopContextManager, didChangeFrontmostApp app: NSRunningApplication?)
}

// MARK: - Classes

/// 단일 애플리케이션의 상태를 감시하고 제어하는 세션
/// (기존 AppSubscription)
@MainActor
final class AppSession {
    // 식별 및 상태
    let appIdentifier: AppIdentifier
    let pid: pid_t
    private let runningApplication: NSRunningApplication

    // 내부 캐시 (WindowID -> Info)
    private(set) var monitoredWindows: [WindowID: WindowInfo] = [:]

    weak var delegate: AppSessionDelegate?

    // AXUIElement 등 내부 구현체
    private let appElement: AXUIElement
    private var axObserver: AXObserver?
    private var observerRefCon: UnsafeMutableRawPointer?

    nonisolated(unsafe) private let observedNotifications: [CFString] = [
        kAXWindowCreatedNotification as CFString,
        kAXUIElementDestroyedNotification as CFString,
        kAXFocusedWindowChangedNotification as CFString,
        kAXMainWindowChangedNotification as CFString,
        kAXWindowMovedNotification as CFString,
        kAXWindowResizedNotification as CFString,
        kAXTitleChangedNotification as CFString,
        kAXMenuOpenedNotification as CFString,
        kAXMenuClosedNotification as CFString,
        kAXMenuItemSelectedNotification as CFString
    ]

    // 디바운스+병합: 잦은 AX 노티를 100~200ms 간격으로 묶고, 실행 중 중복을 한 번으로 합친다.
    private let refreshSubject = PassthroughSubject<Void, Never>()
    private let menuRefreshSubject = PassthroughSubject<Void, Never>()
    /// popup(컨텍스트) 메뉴 open AX 알림을 흘려보내는 파이프라인. 메뉴바와 달리 응답성이
    /// 중요하므로 debounce 가 없다.
    private let contextMenuOpenedSubject = PassthroughSubject<AXUIElement, Never>()
    private let contextMenuClosedSubject = PassthroughSubject<AXUIElement, Never>()
    private var cancellables = Set<AnyCancellable>()
    private let refreshDelay: TimeInterval = 0.05
    private let menuRefreshDelay: TimeInterval = 0.2
    private var isRefreshing = false
    private var pendingRefresh = false
    private var isStopped = false

    nonisolated(unsafe) private static let menuNotifications: Set<String> = [
        kAXMenuOpenedNotification as String,
        kAXMenuClosedNotification as String,
        kAXMenuItemSelectedNotification as String
    ]

    /// 메뉴바 자체 노티는 아니지만, 발생 시 앱이 메뉴 항목 enabled set 을 동적으로
    /// 변경하는 경우가 많아(예: Firefox 가 sheet 첨부 시 메뉴바를 일시적으로 좁힘)
    /// 메뉴 재스냅샷도 함께 트리거한다. 이미 200ms 디바운스가 걸려 있어 폭주
    /// 우려는 없다.
    nonisolated(unsafe) private static let windowFocusNotifications: Set<String> = [
        kAXFocusedWindowChangedNotification as String,
        kAXMainWindowChangedNotification as String
    ]
    
    init(runningApp: NSRunningApplication) throws {
        if let bundleID = runningApp.bundleIdentifier, bundleID.isEmpty == false {
            self.appIdentifier = .bundleID(bundleID)
        } else {
            self.appIdentifier = .processID(runningApp.processIdentifier)
        }
        self.pid = runningApp.processIdentifier
        self.runningApplication = runningApp
        self.appElement = AXUIElementCreateApplication(self.pid)
        
        guard AXIsProcessTrusted() else {
            throw DesktopContextError.accessibilityPermissionMissing
        }
        
        try self.setupObserver()
        self.setupRefreshPipeline()
        self.setupMenuRefreshPipeline()
        self.setupContextMenuPipeline()
        self.monitoredWindows = self.fetchWindowList()
    }
    
    deinit {
        // 정상 흐름에서는 retain cycle(passRetained) 때문에
        // stop() 없이는 deinit에 도달할 수 없음.
        // 이 guard는 방어적 프로그래밍용.
        if !isStopped {
            assertionFailure("AppSession \(appIdentifier) deallocated without stop()")
        }
    }

    // MARK: - Lifecycle

    /// AXObserver 및 Combine 파이프라인을 정리하고 retain cycle을 해소한다.
    /// DesktopContextManager.stopMonitoring(pid:) 에서 호출된다.
    func stop() {
        guard !isStopped else { return }
        isStopped = true

        cancellables.removeAll()

        guard let observer = axObserver else { return }
        for notification in observedNotifications {
            AXObserverRemoveNotification(observer, appElement, notification)
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)

        // passRetained의 +1 retain을 해제 (retain cycle 해소)
        if let refCon = observerRefCon {
            Unmanaged<AppSession>.fromOpaque(refCon).release()
            observerRefCon = nil
        }

        axObserver = nil
    }

    // MARK: - Control Actions
    
    /// 앱 자체를 활성화 (Bring to front)
    func activate() throws {
        try ensureAppIsRunning()
        _ = runningApplication.activate()
    }

    /// 앱 종료 요청
    func terminate() throws {
        try ensureAppIsRunning()
        if !runningApplication.terminate() {
            throw DesktopContextError.appNotRunning
        }
    }
    
    /// 현재 앱의 메뉴바를 `AccessibilityNode` 트리로 스냅샷한다.
    /// - Parameter depth: 최대 재귀 깊이. 음수면 무제한. eager 로드는 2, lazy 요청은 음수 권장.
    /// - Returns: 메뉴바 루트 노드. AX 권한이 없거나 메뉴바를 조회할 수 없으면 nil.
    ///
    /// 호출마다 `AppMenuRegistry`에 새 UUID들이 발급되어 누적된다. 필요하면 호출 전에
    /// `AppMenuRegistry.shared.prune(pid:)`로 기존 매핑을 정리한다.
    func snapshotMenuBar(depth: Int = 2) -> AccessibilityNode? {
        let builder = AccessibilityTreeBuilder(pid: self.pid, maxDepth: depth)
        return builder.snapshotMenuBar(appElement: self.appElement)
    }

    /// 전체 윈도우 정보 강제 갱신 (Polling 방식이 필요할 때 사용)
    func refreshWindows() {
        let previousWindows = self.monitoredWindows
        let previousFocusID = previousWindows.values.first(where: { $0.flags.contains(.isFocused) })?.windowID

        let windows = self.fetchWindowList()
        let newFocusID = windows.values.first(where: { $0.flags.contains(.isFocused) })?.windowID

        self.monitoredWindows = windows

        guard let delegate = self.delegate else { return }

        let added = Set(windows.keys).subtracting(previousWindows.keys)
        let removed = Set(previousWindows.keys).subtracting(windows.keys)
        let candidates = Set(windows.keys).intersection(previousWindows.keys)

        for id in added {
            if let window = windows[id] {
                delegate.appSession(self, didDiscoverWindow: window)
            }
        }

        for id in removed {
            delegate.appSession(self, didCloseWindow: id)
        }

        for id in candidates {
            guard let oldValue = previousWindows[id], let newValue = windows[id] else { continue }
            if oldValue != newValue {
                delegate.appSession(self, didUpdateWindow: newValue)
            }
        }

        if previousFocusID != newFocusID {
            delegate.appSession(self, didChangeWindowFocusTo: newFocusID != nil ? WindowID(newFocusID!) : nil)
        }
    }
    
    /// 특정 윈도우로 포커스 이동 (winman.proto: WindowFocusRequest)
    func focusWindow(id: WindowID) throws {
        try ensureAppIsRunning()
        let windowElement = try self.windowElement(for: id)
        
        let setMainResult = AXUIElementSetAttributeValue(windowElement, kAXMainAttribute as CFString, kCFBooleanTrue)
        if setMainResult != .success {
            throw DesktopContextError.failedToSetFocusedWindow(setMainResult)
        }
        
        let focusResult = AXUIElementSetAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, windowElement)
        if focusResult != .success {
            throw DesktopContextError.failedToSetFocusedWindow(focusResult)
        }
        
        _ = AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)
        
        refreshWindows()
    }
    
    /// 윈도우 닫기
    func closeWindow(id: WindowID) throws {
        try ensureAppIsRunning()
        let windowElement = try self.windowElement(for: id)
        
        var closeButtonValue: CFTypeRef?
        let closeButtonResult = AXUIElementCopyAttributeValue(windowElement, kAXCloseButtonAttribute as CFString, &closeButtonValue)
        guard closeButtonResult == .success else {
            throw DesktopContextError.failedToReadAttribute(kAXCloseButtonAttribute as String, closeButtonResult)
        }
        guard closeButtonValue != nil else {
            throw DesktopContextError.failedToReadAttribute(kAXCloseButtonAttribute as String, .cannotComplete)
        }
        
        let closeButtonElement = closeButtonValue as! AXUIElement
        
        let result = AXUIElementPerformAction(closeButtonElement, kAXPressAction as CFString)
        if result != .success {
            throw DesktopContextError.failedToPerformAction("close", result)
        }
        refreshWindows()
    }
    
    /// 윈도우 이동/크기 조절 (Noctiluca 기능 확장 시 필요)
    func setWindowFrame(id: WindowID, frame: CGRect) throws {
        try ensureAppIsRunning()
        let windowElement = try self.windowElement(for: id)

        // 멀티 디스플레이 (특히 가상 디스플레이가 음수 origin 으로 배치되는 경우) 를
        // 지원하기 위해 origin 을 그대로 전달한다. AX API 는 글로벌 좌표계의 음수 좌표를
        // 그대로 받아들이며, kAXPositionAttribute 는 윈도우가 어느 화면에 속하는지를
        // origin 만으로 재결정한다.
        var origin = frame.origin
        var size = frame.size
        
        guard let positionValue = AXValueCreate(.cgPoint, &origin),
              let sizeValue = AXValueCreate(.cgSize, &size) else {
            throw DesktopContextError.invalidWindowFrame
        }
        
        let positionResult = AXUIElementSetAttributeValue(windowElement, kAXPositionAttribute as CFString, positionValue)
        if positionResult != .success {
            throw DesktopContextError.failedToUpdateWindowFrame(positionResult)
        }
        
        let sizeResult = AXUIElementSetAttributeValue(windowElement, kAXSizeAttribute as CFString, sizeValue)
        if sizeResult != .success {
            throw DesktopContextError.failedToUpdateWindowFrame(sizeResult)
        }
        
        refreshWindows()
    }
    
    // MARK: - Internal Logic
    
    /// AXObserver 콜백 등에서 호출되어 Delegate에게 알림.
    /// `element` 는 알림이 발생한 AX 요소이며, popup 메뉴(컨텍스트 메뉴) 와 메뉴바 산하 메뉴를
    /// 구분하기 위해 사용한다.
    private func handleAXNotification(_ notification: CFString, element: AXUIElement) {
        let name = notification as String

        if name == kAXMenuOpenedNotification as String {
            if Self.isInsideMenuBar(element: element) {
                menuRefreshSubject.send(())
            } else {
                contextMenuOpenedSubject.send(element)
            }
            return
        }

        if name == kAXMenuClosedNotification as String {
            if Self.isInsideMenuBar(element: element) {
                menuRefreshSubject.send(())
            } else {
                contextMenuClosedSubject.send(element)
            }
            return
        }

        if Self.menuNotifications.contains(name) {
            // kAXMenuItemSelectedNotification: popup 의 경우 close 가 뒤따라 오므로 별도 처리하지 않는다.
            menuRefreshSubject.send(())
            return
        }

        refreshSubject.send(())

        if Self.windowFocusNotifications.contains(name) {
            menuRefreshSubject.send(())
        }
    }

    /// 주어진 AX 요소가 메뉴바(AXMenuBar) 산하인지 검사한다. parent 체인을 따라 올라가며 role 을
    /// 확인하고, 적정 depth 안에서 AXMenuBar 를 만나면 true. AppKit popup 메뉴(컨텍스트 메뉴) 는
    /// 메뉴바와 무관한 별도 윈도우에 그려지므로 false 가 된다.
    nonisolated private static func isInsideMenuBar(element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        var depth = 0
        while let elem = current, depth < 12 {
            var roleValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleValue) == .success,
               let role = roleValue as? String,
               role == kAXMenuBarRole as String {
                return true
            }
            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(elem, kAXParentAttribute as CFString, &parentValue) == .success,
                  let raw = parentValue, CFGetTypeID(raw) == AXUIElementGetTypeID() else {
                return false
            }
            current = (raw as! AXUIElement)
            depth += 1
        }
        return false
    }

    private func setupObserver() throws {
        var observer: AXObserver?
        let result = AXObserverCreate(self.pid, { _, element, notification, context in
            guard let context else { return }
            // AXObserver 콜백은 메인 런루프에서 실행되므로 assumeIsolated가 안전함
            MainActor.assumeIsolated {
                let session = Unmanaged<AppSession>.fromOpaque(context).takeUnretainedValue()
                session.handleAXNotification(notification, element: element)
            }
        }, &observer)

        guard result == .success, let observer else {
            throw DesktopContextError.cannotCreateAXObserver(result)
        }

        self.axObserver = observer

        // +1 retain: stop()에서 release하여 retain cycle을 해소함
        let refCon = Unmanaged.passRetained(self).toOpaque()
        self.observerRefCon = refCon

        for notification in observedNotifications {
            _ = AXObserverAddNotification(observer, appElement, notification, refCon)
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
    
    /// AX 노티 폭주를 막기 위한 디바운스 엔트리 포인트 (Combine 기반)
    private func setupRefreshPipeline() {
        let delay = DispatchQueue.SchedulerTimeType.Stride.milliseconds(Int(refreshDelay * 1000))
        refreshSubject
            .debounce(for: delay, scheduler: DispatchQueue.main)
            .sink { [weak self] in
                self?.enqueueRefresh()
            }
            .store(in: &cancellables)
    }

    /// 메뉴 변경 노티 디바운스 파이프라인. snapshotMenuBar → delegate 전파를 트리거한다.
    private func setupMenuRefreshPipeline() {
        let delay = DispatchQueue.SchedulerTimeType.Stride.milliseconds(Int(menuRefreshDelay * 1000))
        menuRefreshSubject
            .debounce(for: delay, scheduler: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                // AppMenuRegistry가 CFEqual 기반으로 UUID를 재사용하므로 prune 없이 호출한다.
                // 기존 UUID는 그대로 유효하여 in-flight DispatchAction 요청이 실패하지 않는다.
                if let root = self.snapshotMenuBar(depth: 2) {
                    self.delegate?.appSession(self, didUpdateMenuBar: root)
                }
            }
            .store(in: &cancellables)
    }

    /// 명시적으로 메뉴 재스냅샷을 요청한다. 폴링 fallback 등에서 사용한다.
    func requestMenuRefresh() {
        menuRefreshSubject.send(())
    }

    /// popup(컨텍스트) 메뉴 open/close 알림을 delegate 에 전달하는 파이프라인.
    /// 메뉴바와 달리 응답성이 중요하므로 debounce 없이 즉시 dispatch 한다.
    private func setupContextMenuPipeline() {
        contextMenuOpenedSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] element in
                self?.dispatchContextMenuOpened(element: element)
            }
            .store(in: &cancellables)

        contextMenuClosedSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] element in
                self?.dispatchContextMenuClosed(element: element)
            }
            .store(in: &cancellables)
    }

    private func dispatchContextMenuOpened(element: AXUIElement) {
        let builder = AccessibilityTreeBuilder(pid: self.pid, maxDepth: 2)
        let tree = builder.snapshot(subtreeRoot: element, parentId: nil)

        let bounds = Self.readPopupBounds(element: element)
        // 현재 focus 된 윈도우를 트리거 윈도우 후보로 사용한다.
        let triggerWindowID: WindowID? = monitoredWindows
            .first(where: { $0.value.flags.contains(.isFocused) })?.key

        delegate?.appSession(
            self,
            didOpenContextMenu: tree,
            hostBounds: bounds,
            triggerWindowID: triggerWindowID
        )
    }

    private func dispatchContextMenuClosed(element: AXUIElement) {
        guard let menuID = AppMenuRegistry.shared.lookup(element: element, pid: pid) else {
            // 등록되지 않은 element 의 close 는 무시한다 (예: popup open 알림이 우리에게 닿기 전에
            // 사용자가 닫은 경우, 혹은 prune 후 stale 한 close).
            return
        }
        delegate?.appSession(self, didCloseContextMenu: menuID)
    }

    nonisolated private static func readPopupBounds(element: AXUIElement) -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero

        var positionValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
           let raw = positionValue, CFGetTypeID(raw) == AXValueGetTypeID() {
            AXValueGetValue(raw as! AXValue, .cgPoint, &origin)
        }
        var sizeValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
           let raw = sizeValue, CFGetTypeID(raw) == AXValueGetTypeID() {
            AXValueGetValue(raw as! AXValue, .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }

    /// 실제 refresh 실행을 직렬화하고, 실행 중 추가 요청은 한 번 더 실행하도록 병합
    private func enqueueRefresh() {
        guard !isRefreshing else {
            pendingRefresh = true
            return
        }
        isRefreshing = true
        defer {
            isRefreshing = false
            if pendingRefresh {
                pendingRefresh = false
                enqueueRefresh()
            }
        }
        refreshWindows()
    }
    
    private func ensureAppIsRunning() throws {
        if self.runningApplication.isTerminated {
            throw DesktopContextError.appNotRunning
        }
    }
    
    private func windowElement(for id: WindowID) throws -> AXUIElement {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard result == .success else {
            throw DesktopContextError.failedToReadAttribute(kAXWindowsAttribute as String, result)
        }
        
        guard let windows = value as? [AXUIElement] else {
            throw DesktopContextError.failedToReadAttribute(kAXWindowsAttribute as String, .cannotComplete)
        }
        
        for element in windows {
            var number: CGWindowID = 0
            
            guard let error = ApplicationServicesPrivate._AXUIElementGetWindow?(element, &number),
                  error == .success
            else {
                continue
            }
            
            if number == id {
                return element
            }
        }
        
        throw DesktopContextError.windowNotFound(id)
    }
    
    /// appElement의 AX 윈도우 목록을 한 번 순회하여 CGWindowID -> AXUIElement 맵 생성
    private func buildAXWindowMap() -> [CGWindowID: AXUIElement] {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        guard result == .success, let windows = value as? [AXUIElement] else {
            return [:]
        }

        var map: [CGWindowID: AXUIElement] = [:]
        for element in windows {
            var number: CGWindowID = 0
            guard let error = ApplicationServicesPrivate._AXUIElementGetWindow?(element, &number),
                  error == .success else {
                continue
            }
            map[number] = element
        }
        return map
    }

    private func axFocusedWindowID() -> WindowID? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value)
        guard result == .success, value != nil else {
            return nil
        }
        
        let focusedWindow = value as! AXUIElement
        
        var windowNumberValue: CFTypeRef?
        let numberResult = AXUIElementCopyAttributeValue(focusedWindow, kAXWindowNumberAttribute as CFString, &windowNumberValue)
        guard numberResult == .success, let number = windowNumberValue as? NSNumber else {
            return nil
        }
        
        return WindowID(number.uint32Value)
    }
    
    private func fetchWindowList() -> [WindowID: WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return [:]
        }
        
        let appWindows = infoList.filter { info in
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t else { return false }
            return ownerPID == self.pid
        }
        
        let focusedID = self.axFocusedWindowID() ?? appWindows.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }.first
        let axWindowMap = self.buildAXWindowMap()

        return Dictionary(uniqueKeysWithValues: appWindows.compactMap { info in
            guard info.keys.contains(kCGWindowBounds as String) else {
                return nil
            }

            let boundsDictionary = info[kCGWindowBounds as String] as! CFDictionary

            guard let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else {
                return nil
            }

            let windowID = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            let layer = Int32(info[kCGWindowLayer as String] as? Int ?? 0)
            let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let title = info[kCGWindowName as String] as? String ?? ""
            let isOnscreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 0.0
            let isVisible = isOnscreen && alpha > 0.01
            let isActive = focusedID == windowID

            let axAttrs: AXWindowAttributes
            if let axElement = axWindowMap[windowID] {
                axAttrs = readAXWindowAttributes(from: axElement)
            } else {
                axAttrs = .empty
            }

            guard let axRole = axAttrs.axRole,
                  let axSubrole = axAttrs.axSubrole
            else {
                // HACK(Xcode): treat as closed window when axRole is nil (shift-f2)
                return nil
            }

            guard let skyLightWindowInfo = getSkyLightWindowInfo(for: windowID) else {
                return nil
            }

            let signals = deriveWindowInfoSignals(
                axAttrs: axAttrs,
                skyLightInfo: skyLightWindowInfo,
                isFocused: isActive,
                isOnscreen: isOnscreen,
                isVisible: isVisible,
                layer: layer
            )

            var metadata: [String: String] = [
                "app.noctiluca.server.x-window-layer": "\(layer)",
                "app.noctiluca.server.x-window-alpha": "\(alpha)",
                "app.noctiluca.server.x-axrole": axRole,
                "app.noctiluca.server.x-axsubrole": axSubrole,
            ]
            metadata.merge(signals.metadataExtras) { _, new in new }

            let bundleID = runningApplication.bundleIdentifier ?? "app.noctiluca.server.UnknownBundleID"

            let parentWindowID = if let cgParentWindowID = skyLightWindowInfo.parentWindowId {
                UInt64(cgParentWindowID)
            } else {
                UInt64(0)
            }

            let windowInfo = WindowInfo(
                windowID: UInt64(windowID),
                pid: UInt64(ownerPID),
                windowTitle: title,
                applicationName: runningApplication.localizedName ?? "(unknown)",
                applicationBundleID: bundleID,
                windowClass: axAttrs.axClassName ?? bundleID,
                role: axAttrs.windowRole,
                parentWindowID: parentWindowID,
                bounds: SRRect(x: bounds.origin.x, y: bounds.origin.y, width: bounds.size.width, height: bounds.size.height),
                iconHash: nil,
                thumbnail: nil,
                metadata: metadata,
                hints: signals.hints,
                flags: signals.flags
            )

            // FIXME: ...
            if windowInfo.isNSLocalWindowSharingWindow || !windowInfo.isStandaloneWindow {
                return nil
            }
            
            return (windowID, windowInfo)
        })
    }
}

// MARK: - Window Event Subscription

struct WindowEventSubscription {
    let id: UUID
    let eventMask: WindowChangeEventType
    let filter: WindowFilter?
    let flags: WindowEventSubscriptionFlagSet
    let callback: @MainActor @Sendable (WindowChangedEvent) -> Void
}

// MARK: - App Event Subscription

struct AppEventSubscription {
    let id: UUID
    let eventMask: ApplicationEventType
    let bundleIdFilter: String?
    let callback: @MainActor @Sendable (ApplicationChangedEvent) -> Void
}

// MARK: - Menu Event Subscription

struct MenuEventSubscription {
    let id: UUID
    let pid: pid_t
    /// 메뉴바 재스냅샷 결과를 전달받는 콜백. `root`는 `AccessibilityNode(role=menu)`이다.
    let callback: @MainActor @Sendable (AccessibilityNode) -> Void
}

// MARK: - Context Menu Event Subscription

/// popup(컨텍스트) 메뉴 이벤트. 메뉴바 갱신과 별개로 처리한다.
/// 클라이언트 송신 시점에 일반 `AccessibilityTreeUpdateEvent` 로 변환된다.
enum ContextMenuEvent: Sendable {
    /// 메뉴가 새로 떴음을 알린다. `tree.id` 가 곧 menuId 이다.
    case opened(tree: AccessibilityNode, hostBounds: CGRect, triggerWindowID: WindowID?)
    /// 메뉴가 호스트 측에서 닫혔음을 알린다.
    case closed(menuID: UUID)
}

struct ContextMenuEventSubscription {
    let id: UUID
    let pid: pid_t
    let callback: @MainActor @Sendable (ContextMenuEvent) -> Void
}

/// 시스템 전체의 앱 실행 상태와 포커스를 관장하는 매니저
/// (기존 WindowManagerOrSpy)
@MainActor
final class DesktopContextManager {
    public static let shared = DesktopContextManager()

    private let logger = NoctilucaLogger(category: "DesktopContextManager")

    weak var delegate: DesktopContextManagerDelegate?

    /// 현재 감시 중인 앱 세션들 (PID: Session)
    private(set) var activeSessions: [pid_t: AppSession] = [:]

    /// 활성 윈도우 이벤트 구독 (SubscriptionID: Subscription)
    private var subscriptions: [UUID: WindowEventSubscription] = [:]

    /// 활성 앱 이벤트 구독 (SubscriptionID: Subscription)
    private var appEventSubscriptions: [UUID: AppEventSubscription] = [:]

    /// 활성 메뉴 이벤트 구독 (SubscriptionID: Subscription)
    private var menuEventSubscriptions: [UUID: MenuEventSubscription] = [:]

    /// 활성 컨텍스트(popup) 메뉴 이벤트 구독
    private var contextMenuEventSubscriptions: [UUID: ContextMenuEventSubscription] = [:]

    private let workspace: NSWorkspace
    private var workspaceObservers: [Any] = []

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace

        Task { [weak self] in
            await self?.registerWorkspaceNotifications()
        }
    }
    
    @MainActor
    deinit {
        workspaceObservers.forEach { observer in
            workspace.notificationCenter.removeObserver(observer)
        }
    }

    // MARK: - Public Methods

    /// 권한 확인 (Screen Recording, Accessibility)
    func checkPermissions() -> Bool {
        let accessibilityOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let accessibilityGranted = AXIsProcessTrustedWithOptions(accessibilityOptions)

        let screenRecordingGranted: Bool
        if #available(macOS 10.15, *) {
            screenRecordingGranted = CGPreflightScreenCaptureAccess()
        } else {
            screenRecordingGranted = true
        }

        return accessibilityGranted && screenRecordingGranted
    }

    func runningApplications() -> [NSRunningApplication] {
        return workspace.runningApplications.filter(shouldMonitor)
    }

    func frontmostApplication() -> NSRunningApplication? {
        return workspace.frontmostApplication
    }

    /// 현재 실행 중인 모든 앱 스캔 (초기화 용)
    func scanRunningApplications() {
        workspace.runningApplications
            .filter(shouldMonitor)
            .forEach { app in
                delegate?.desktopManager(self, didDetectAppLaunch: app)
            }

        delegate?.desktopManager(self, didChangeFrontmostApp: workspace.frontmostApplication)
    }

    /// 특정 앱을 감시 시작
    /// - Returns: 생성된 AppSession 객체
    func startMonitoring(app: NSRunningApplication) throws -> AppSession {
        if let existing = activeSessions[app.processIdentifier] {
            return existing
        }

        let session = try AppSession(runningApp: app)
        session.delegate = self
        activeSessions[app.processIdentifier] = session
        return session
    }

    /// 감시 중단
    func stopMonitoring(pid: pid_t) {
        if let session = activeSessions.removeValue(forKey: pid) {
            session.stop()
        }
    }

    /// 모든 세션을 정리하고 workspace observer를 해제한다.
    func shutdown() {
        subscriptions.removeAll()
        appEventSubscriptions.removeAll()
        for session in activeSessions.values {
            session.stop()
        }
        activeSessions.removeAll()
        workspaceObservers.forEach { observer in
            workspace.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    // MARK: - Window Info Query

    /// windowID로 캐시된 세션에서 WindowInfo 조회
    func windowInfo(for windowID: WindowID) -> WindowInfo? {
        for session in activeSessions.values {
            if let info = session.monitoredWindows[windowID] {
                return info
            }
        }
        return nil
    }

    /// windowID로 윈도우 bounds(CGRect) 조회 (thread-safe, CGWindowList 기반)
    ///
    /// `CGWindowListCopyWindowInfo`는 thread-safe이므로 MainActor 외부에서도 호출 가능하다.
    /// TTL 캐시를 사용하여 마우스 이벤트마다 발생하는 CGWindowList IPC를 최소화한다.
    nonisolated private static let boundsCacheTTL: CFAbsoluteTime = 0.5

    private static let boundsCache = OSAllocatedUnfairLock(initialState: (
        windowID: WindowID(0),
        bounds: CGRect.zero,
        timestamp: CFAbsoluteTime(0)
    ))

    static func queryWindowBounds(for windowID: WindowID) -> CGRect? {
        let now = CFAbsoluteTimeGetCurrent()

        let cached: CGRect? = boundsCache.withLock { state in
            guard state.windowID == windowID,
                  (now - state.timestamp) < boundsCacheTTL else {
                return nil
            }
            return state.bounds
        }
        if let cached { return cached }

        guard let infoList = CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]],
              let info = infoList.first,
              info.keys.contains(kCGWindowBounds as String)
        else {
            return nil
        }
        let boundsCF = info[kCGWindowBounds as String] as! CFDictionary
        guard let bounds = CGRect(dictionaryRepresentation: boundsCF) else {
            return nil
        }

        boundsCache.withLock { state in
            state = (windowID, bounds, now)
        }
        return bounds
    }

    // MARK: - AppStream Helper Window Bounds

    /// AppStream으로 윈도우를 캡쳐하는 동안 WindowServer가 신호등 자리에 그리는
    /// "Screen Sharing Helper" 다이얼로그는 ScreenCaptureKit 출력에 포함되지 않아
    /// 클라이언트에는 보이지 않는다. 클라이언트 마우스 입력이 이 영역에 들어가면
    /// 호스트에서 캡쳐 중지/창 닫기 메뉴가 잘못 트리거될 수 있어 HIDIO 인젝션
    /// 단계에서 차단할 때 사용한다.
    ///
    /// 판정 조건은 `WindowInfo.isNSLocalWindowSharingWindow` 와 동일하며
    /// (size 60×20 또는 66×20 + AX role = dialog), 마우스 이벤트마다 호출될 수
    /// 있어 TTL 캐시를 적용한다.
    nonisolated private static let helperWindowBoundsCacheTTL: CFAbsoluteTime = 0.5

    private static let helperWindowBoundsCache = OSAllocatedUnfairLock(initialState: (
        bounds: [CGRect](),
        timestamp: CFAbsoluteTime(0)
    ))

    @MainActor
    static func appStreamHelperWindowBounds() -> [CGRect] {
        let now = CFAbsoluteTimeGetCurrent()

        let cached: [CGRect]? = helperWindowBoundsCache.withLock { state in
            guard (now - state.timestamp) < helperWindowBoundsCacheTTL else {
                return nil
            }
            return state.bounds
        }
        if let cached { return cached }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        // size 조건이 가장 변별력 있으므로 먼저 필터링하여 AX 쿼리 횟수를 최소화한다.
        let candidates = infoList.compactMap { info -> (pid_t, CGWindowID, CGRect)? in
            guard info.keys.contains(kCGWindowBounds as String) else { return nil }
            let boundsDictionary = info[kCGWindowBounds as String] as! CFDictionary
            guard let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  (bounds.width == 66 || bounds.width == 60) && bounds.height == 20,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID
            else {
                return nil
            }
            return (pid, windowID, bounds)
        }

        var axMapsByPID: [pid_t: [CGWindowID: AXUIElement]] = [:]
        var collected: [CGRect] = []

        for (pid, windowID, bounds) in candidates {
            let axMap: [CGWindowID: AXUIElement]
            if let cachedMap = axMapsByPID[pid] {
                axMap = cachedMap
            } else {
                var map: [CGWindowID: AXUIElement] = [:]
                let appElement = AXUIElementCreateApplication(pid)
                var value: CFTypeRef?
                let result = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
                if result == .success, let windows = value as? [AXUIElement] {
                    for element in windows {
                        var number: CGWindowID = 0
                        guard let error = ApplicationServicesPrivate._AXUIElementGetWindow?(element, &number),
                              error == .success else { continue }
                        map[number] = element
                    }
                }
                axMapsByPID[pid] = map
                axMap = map
            }

            guard let axElement = axMap[windowID] else { continue }
            let axRole = axStringAttribute(axElement, kAXRoleAttribute as String)
            let axSubrole = axStringAttribute(axElement, kAXSubroleAttribute as String)
            guard mapAXRoleToWindowRole(axRole: axRole, axSubrole: axSubrole) == .dialog else { continue }

            collected.append(bounds)
        }

        let helpers = collected
        helperWindowBoundsCache.withLock { state in
            state = (helpers, now)
        }
        return helpers
    }

    // MARK: - Window ID Lookup

    /// CGWindowList에서 windowID의 소유 pid를 조회 (on-demand)
    func findOwnerPID(windowID: WindowID) -> pid_t? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for info in infoList {
            guard let wid = info[kCGWindowNumber as String] as? CGWindowID,
                  wid == windowID,
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t else {
                continue
            }
            return pid
        }
        return nil
    }

    /// windowID로 NSRunningApplication 조회
    func findRunningApplication(forWindowID windowID: WindowID) -> NSRunningApplication? {
        guard let pid = findOwnerPID(windowID: windowID) else { return nil }
        return NSRunningApplication(processIdentifier: pid)
    }

    // MARK: - Lazy Session Management

    /// windowID 기반으로 AppSession을 자동 생성/반환
    func ensureSession(forWindowID windowID: WindowID) throws -> AppSession {
        guard let pid = findOwnerPID(windowID: windowID) else {
            throw DesktopContextError.windowOwnerNotFound(windowID)
        }
        return try ensureSession(forPID: pid)
    }

    /// pid 기반으로 AppSession을 자동 생성/반환
    private func ensureSession(forPID pid: pid_t) throws -> AppSession {
        if let existing = activeSessions[pid] {
            return existing
        }
        guard let app = NSRunningApplication(processIdentifier: pid) else {
            throw DesktopContextError.appNotRunning
        }
        return try startMonitoring(app: app)
    }

    // MARK: - Window Manipulation (Convenience)

    /// 특정 윈도우로 포커스 이동
    func focusWindow(id: WindowID) throws {
        let session = try ensureSession(forWindowID: id)
        try session.activate()
        try session.focusWindow(id: id)
    }

    /// 윈도우 닫기
    func closeWindow(id: WindowID) throws {
        let session = try ensureSession(forWindowID: id)
        try session.closeWindow(id: id)
    }

    /// 윈도우 이동/크기 조절
    func setWindowFrame(id: WindowID, frame: CGRect) throws {
        let session = try ensureSession(forWindowID: id)
        try session.setWindowFrame(id: id, frame: frame)
    }

    /// WindowStateCommand 기반 조작
    func sendStateCommand(id: WindowID, command: WindowStateCommand) throws {
        switch command {
        case .close:
            try closeWindow(id: id)
        case .minimize, .maximize, .restore:
            throw DesktopContextError.unsupportedOperation("WindowStateCommand.\(command) is not yet supported")
        default:
            throw DesktopContextError.unsupportedOperation("Unknown WindowStateCommand")
        }
    }

    // MARK: - Window Event Subscription

    /// 윈도우 이벤트 구독 등록
    func subscribeWindowEvents(
        eventMask: WindowChangeEventType,
        filter: WindowFilter?,
        flags: WindowEventSubscriptionFlagSet,
        callback: @escaping @MainActor @Sendable (WindowChangedEvent) -> Void
    ) -> UUID {
        let subscriptionID = UUID()
        let subscription = WindowEventSubscription(
            id: subscriptionID,
            eventMask: eventMask,
            filter: filter,
            flags: flags,
            callback: callback
        )
        subscriptions[subscriptionID] = subscription

        // 구독 대상 앱들의 AppSession 자동 생성
        ensureSessionsForSubscription(subscription)

        // sendInitialSnapshot 플래그 처리
        if flags.contains(.sendInitialSnapshot) {
            let windowList = globalWindowList()
            for window in windowList {
                if let filter, !filter.matches(window) { continue }
                let event = WindowChangedEvent(
                    eventType: .metadataChanged,
                    windowID: window.windowID,
                    info: window
                )
                callback(event)
            }
        }

        return subscriptionID
    }

    /// 윈도우 이벤트 구독 해제
    func unsubscribeWindowEvents(id: UUID) -> Bool {
        return subscriptions.removeValue(forKey: id) != nil
    }

    // MARK: - App Event Subscription

    /// 앱 이벤트 구독 등록
    func subscribeAppEvents(
        eventMask: ApplicationEventType,
        bundleIdFilter: String?,
        callback: @escaping @MainActor @Sendable (ApplicationChangedEvent) -> Void
    ) -> UUID {
        let id = UUID()
        let subscription = AppEventSubscription(
            id: id,
            eventMask: eventMask,
            bundleIdFilter: bundleIdFilter,
            callback: callback
        )
        appEventSubscriptions[id] = subscription
        return id
    }

    /// 앱 이벤트 구독 해제
    func unsubscribeAppEvents(id: UUID) -> Bool {
        return appEventSubscriptions.removeValue(forKey: id) != nil
    }

    // MARK: - Menu Event Subscription

    /// 메뉴바 변경 이벤트 구독 등록. pid가 현재 감시 중인 AppSession이 아니면 callback은 호출되지 않는다.
    /// - Parameter pid: 감시 대상 앱의 PID
    /// - Parameter callback: 메뉴바 스냅샷이 갱신될 때 호출되는 핸들러 (root는 role=menu 노드)
    /// - Returns: 구독 UUID
    func subscribeMenuEvents(
        pid: pid_t,
        callback: @escaping @MainActor @Sendable (AccessibilityNode) -> Void
    ) -> UUID {
        let id = UUID()
        menuEventSubscriptions[id] = MenuEventSubscription(id: id, pid: pid, callback: callback)
        return id
    }

    /// 메뉴 이벤트 구독 해제
    @discardableResult
    func unsubscribeMenuEvents(id: UUID) -> Bool {
        return menuEventSubscriptions.removeValue(forKey: id) != nil
    }

    // MARK: - Context Menu (Popup) Event Subscription

    /// 컨텍스트(popup) 메뉴 이벤트 구독 등록.
    func subscribeContextMenuEvents(
        pid: pid_t,
        callback: @escaping @MainActor @Sendable (ContextMenuEvent) -> Void
    ) -> UUID {
        let id = UUID()
        contextMenuEventSubscriptions[id] = ContextMenuEventSubscription(id: id, pid: pid, callback: callback)
        return id
    }

    /// 컨텍스트(popup) 메뉴 이벤트 구독 해제
    @discardableResult
    func unsubscribeContextMenuEvents(id: UUID) -> Bool {
        return contextMenuEventSubscriptions.removeValue(forKey: id) != nil
    }

    // MARK: - App Management Helpers

    /// 번들 ID로 실행 중인 앱 조회
    func findRunningApplication(bundleId: String) -> NSRunningApplication? {
        return workspace.runningApplications.first {
            $0.bundleIdentifier == bundleId && !$0.isTerminated
        }
    }

    /// 번들 ID로 앱 실행
    func launchApplication(bundleId: String, arguments: [String] = []) async throws -> NSRunningApplication {
        guard let appURL = workspace.urlForApplication(withBundleIdentifier: bundleId) else {
            throw DesktopContextError.appNotRunning
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = arguments
        configuration.activates = true

        return try await workspace.openApplication(at: appURL, configuration: configuration)
    }

    /// 번들 ID로 실행 중인 앱 종료
    func terminateApplication(bundleId: String, force: Bool) throws -> Bool {
        guard let app = findRunningApplication(bundleId: bundleId) else {
            throw DesktopContextError.appNotRunning
        }
        return force ? app.forceTerminate() : app.terminate()
    }

    /// 특정 PID의 앱이 소유한 윈도우 목록 반환
    func getWindowsForApp(pid: pid_t, ignoreInvisible: Bool = false) -> [WindowInfo] {
        var windows = globalWindowList().filter { $0.pid == UInt64(pid) }
        if ignoreInvisible {
            windows = windows.filter { !$0.flags.contains(.isHidden) }
        }
        
        print(windows)
        return windows
    }

    // MARK: - Global Window Queries
    
    /// 현재 화면에 있는 모든 윈도우 리스트 조회 (CGWindowList 활용)
    func globalWindowList() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let runningApps = self.runningApplications()
        let frontmostWindowID = infoList.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }.first
        let axWindowMaps = self.buildGlobalAXWindowMaps(from: infoList)

        return infoList.compactMap { info in
            guard info.keys.contains(kCGWindowBounds as String) else {
                return nil
            }

            let boundsDictionary = info[kCGWindowBounds as String] as! CFDictionary
            guard let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else {
                return nil
            }

            let windowID = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            let layer = Int32(info[kCGWindowLayer as String] as? Int ?? 0)
            let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let title = info[kCGWindowName as String] as? String ?? ""
            let isOnscreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 0.0
            let isVisible = isOnscreen && alpha > 0.01
            let isActive = frontmostWindowID == windowID

            let relatedApp = runningApps.first { app in
                app.processIdentifier == ownerPID
            }

            let axAttrs: AXWindowAttributes
            if let axElement = axWindowMaps[ownerPID]?[windowID] {
                axAttrs = readAXWindowAttributes(from: axElement)
            } else {
                axAttrs = .empty
            }

            guard let axRole = axAttrs.axRole,
                  let axSubrole = axAttrs.axSubrole
            else {
                // HACK(Xcode): treat as closed window when axRole is nil (shift-f2)
                return nil
            }

            guard let skyLightWindowInfo = getSkyLightWindowInfo(for: windowID) else {
                return nil
            }

            let signals = deriveWindowInfoSignals(
                axAttrs: axAttrs,
                skyLightInfo: skyLightWindowInfo,
                isFocused: isActive,
                isOnscreen: isOnscreen,
                isVisible: isVisible,
                layer: layer
            )

            var metadata: [String: String] = [
                "app.noctiluca.server.x-window-layer": "\(layer)",
                "app.noctiluca.server.x-window-alpha": "\(alpha)",
                "app.noctiluca.server.x-axrole": axRole,
                "app.noctiluca.server.x-axsubrole": axSubrole,
            ]
            metadata.merge(signals.metadataExtras) { _, new in new }

            let bundleID = relatedApp?.bundleIdentifier ?? "app.noctiluca.server.UnknownBundleID"

            let parentWindowID = if let cgParentWindowID = skyLightWindowInfo.parentWindowId {
                UInt64(cgParentWindowID)
            } else {
                UInt64(0)
            }

            let windowInfo = WindowInfo(
                windowID: UInt64(windowID),
                pid: UInt64(ownerPID),
                windowTitle: title,
                applicationName: relatedApp?.localizedName ?? "(unknown)",
                applicationBundleID: bundleID,
                windowClass: axAttrs.axClassName ?? bundleID,
                role: axAttrs.windowRole,
                parentWindowID: parentWindowID,
                bounds: SRRect(x: bounds.origin.x, y: bounds.origin.y, width: bounds.size.width, height: bounds.size.height),
                iconHash: nil,
                thumbnail: nil,
                metadata: metadata,
                hints: signals.hints,
                flags: signals.flags
            )
            
            if windowInfo.isNSLocalWindowSharingWindow || !windowInfo.isStandaloneWindow {
                return nil
            }
            
            return windowInfo
        }
    }
    
    // MARK: - Private

    /// CGWindowList의 고유 PID들에 대해 AXUIElement 윈도우 맵을 일괄 구성한다.
    private func buildGlobalAXWindowMaps(from infoList: [[String: Any]]) -> [pid_t: [CGWindowID: AXUIElement]] {
        let pids = Set(infoList.compactMap { $0[kCGWindowOwnerPID as String] as? pid_t })
        var result: [pid_t: [CGWindowID: AXUIElement]] = [:]

        for pid in pids {
            let appElement = AXUIElementCreateApplication(pid)

            var value: CFTypeRef?
            let axResult = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
            guard axResult == .success, let windows = value as? [AXUIElement] else {
                continue
            }

            var map: [CGWindowID: AXUIElement] = [:]
            for element in windows {
                var number: CGWindowID = 0
                guard let error = ApplicationServicesPrivate._AXUIElementGetWindow?(element, &number),
                      error == .success else {
                    continue
                }
                map[number] = element
            }
            result[pid] = map
        }

        return result
    }

    private func registerWorkspaceNotifications() {
        let center = workspace.notificationCenter
        let queue = OperationQueue.main
        
        let launchObserver = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: queue
        ) { [weak self] notification in
            // OperationQueue.main에서 실행되므로 assumeIsolated가 안전함
            MainActor.assumeIsolated {
                guard let self, let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                    return
                }
                self.logger.info("[Workspace] app launched: \(app.localizedName ?? "?") (\(app.bundleIdentifier ?? "?"), pid=\(app.processIdentifier))")
                self.delegate?.desktopManager(self, didDetectAppLaunch: app)

                let appInfo = ApplicationInfo(
                    bundleId: app.bundleIdentifier ?? "",
                    displayName: app.localizedName ?? "",
                    state: .foreground,
                    windows: [],
                    icon: nil,
                    metadata: [:],
                    hints: 0,
                    flags: 0
                )
                self.dispatchAppEvent(
                    ApplicationChangedEvent(eventType: .launched, info: appInfo),
                    bundleId: app.bundleIdentifier
                )
            }
        }

        let terminationObserver = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: queue
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                    return
                }
                self.logger.info("[Workspace] app terminated: \(app.localizedName ?? "?") (\(app.bundleIdentifier ?? "?"), pid=\(app.processIdentifier))")
                if let session = self.activeSessions[app.processIdentifier] {
                    session.delegate?.appSessionDidTerminate(session)
                }
                self.stopMonitoring(pid: app.processIdentifier)
                self.delegate?.desktopManager(self, didDetectAppTermination: app.processIdentifier)

                let appInfo = ApplicationInfo(
                    bundleId: app.bundleIdentifier ?? "",
                    displayName: app.localizedName ?? "",
                    state: .notRunning,
                    windows: [],
                    icon: nil,
                    metadata: [:],
                    hints: 0,
                    flags: 0
                )
                self.dispatchAppEvent(
                    ApplicationChangedEvent(eventType: .terminated, info: appInfo),
                    bundleId: app.bundleIdentifier
                )
            }
        }

        let activationObserver = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: queue
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self else { return }
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let activatedApp = app ?? self.workspace.frontmostApplication
                self.logger.info("[Workspace] app activated: \(activatedApp?.localizedName ?? "?") (\(activatedApp?.bundleIdentifier ?? "?"), pid=\(activatedApp?.processIdentifier ?? -1))")
                self.delegate?.desktopManager(self, didChangeFrontmostApp: activatedApp)

                if let activatedApp {
                    let appInfo = ApplicationInfo(
                        bundleId: activatedApp.bundleIdentifier ?? "",
                        displayName: activatedApp.localizedName ?? "",
                        state: .foreground,
                        windows: [],
                        icon: nil,
                        metadata: [:],
                        hints: 0,
                        flags: 0
                    )
                    self.dispatchAppEvent(
                        ApplicationChangedEvent(eventType: .focused, info: appInfo),
                        bundleId: activatedApp.bundleIdentifier
                    )
                }
            }
        }
        
        self.workspaceObservers.append(contentsOf: [launchObserver, terminationObserver, activationObserver])
    }
    
    private func shouldMonitor(_ app: NSRunningApplication) -> Bool {
        guard app.isTerminated == false else { return false }
        return app.activationPolicy != .prohibited
    }

    // MARK: - App Event Dispatch

    /// 앱 이벤트를 모든 매칭되는 구독에 전달
    private func dispatchAppEvent(_ event: ApplicationChangedEvent, bundleId: String?) {
        for subscription in appEventSubscriptions.values {
            guard subscription.eventMask.rawValue & event.eventType.rawValue != 0 else { continue }
            if let filter = subscription.bundleIdFilter, let bundleId, filter != bundleId {
                continue
            }
            subscription.callback(event)
        }
    }

    // MARK: - Subscription Helpers

    /// 구독 필터에서 pid를 추출하여 해당 앱의 AppSession을 자동 생성
    private func ensureSessionsForSubscription(_ subscription: WindowEventSubscription) {
        // 필터에서 pid를 추출할 수 있으면 해당 앱만
        if let filter = subscription.filter, let pids = filter.extractPIDs() {
            for pid in pids {
                do {
                    _ = try ensureSession(forPID: pid)
                } catch {
                    logger.warning("Failed to create session for PID \(pid): \(error)")
                }
            }
        } else {
            // 필터가 없거나 pid를 특정할 수 없으면 모든 모니터링 대상 앱의 세션 생성
            for app in runningApplications() {
                do {
                    _ = try startMonitoring(app: app)
                } catch {
                    logger.warning("Failed to create session for \(app.localizedName ?? "unknown"): \(error)")
                }
            }
        }
    }

    /// 이벤트를 모든 매칭되는 구독에 전달
    private func dispatchWindowEvent(_ event: WindowChangedEvent) {
        for subscription in subscriptions.values {
            // 이벤트 마스크 체크
            guard subscription.eventMask.rawValue & event.eventType.rawValue != 0 else { continue }

            // 필터 체크
            if let filter = subscription.filter, let info = event.info {
                guard filter.matches(info) else { continue }
            }

            subscription.callback(event)
        }
    }
}

// MARK: - AppSessionDelegate

extension DesktopContextManager: AppSessionDelegate {
    func appSessionDidTerminate(_ session: AppSession) {
        logger.info("[\(session.appIdentifier)] app terminated (windows: \(session.monitoredWindows.count))")
        // 해당 앱의 모든 윈도우에 closed 이벤트
        for (windowID, _) in session.monitoredWindows {
            let event = WindowChangedEvent(
                eventType: .closed,
                windowID: UInt64(windowID),
                info: nil
            )
            dispatchWindowEvent(event)
        }
    }

    func appSession(_ session: AppSession, didEncounterError error: Error) {
        logger.warning("AppSession \(session.appIdentifier) error: \(error)")
    }

    func appSessionDidBecomeActive(_ session: AppSession) {
        logger.info("[\(session.appIdentifier)] became active")
    }

    func appSessionDidResignActive(_ session: AppSession) {
        logger.info("[\(session.appIdentifier)] resigned active")
    }

    func appSession(_ session: AppSession, didUpdateMenuBar rootNode: AccessibilityNode) {
        logger.debug("[\(session.appIdentifier)] menu updated: \(rootNode.children.count) top-level item(s)")
        let targets = menuEventSubscriptions.values.filter { $0.pid == session.pid }
        for subscription in targets {
            subscription.callback(rootNode)
        }
    }

    func appSession(
        _ session: AppSession,
        didOpenContextMenu tree: AccessibilityNode,
        hostBounds: CGRect,
        triggerWindowID: WindowID?
    ) {
        logger.debug("[\(session.appIdentifier)] context menu opened: \(tree.children.count) item(s) at \(hostBounds.debugDescription)")
        let event = ContextMenuEvent.opened(tree: tree, hostBounds: hostBounds, triggerWindowID: triggerWindowID)
        let targets = contextMenuEventSubscriptions.values.filter { $0.pid == session.pid }
        for subscription in targets {
            subscription.callback(event)
        }
    }

    func appSession(_ session: AppSession, didCloseContextMenu menuID: UUID) {
        logger.debug("[\(session.appIdentifier)] context menu closed: \(menuID)")
        let event = ContextMenuEvent.closed(menuID: menuID)
        let targets = contextMenuEventSubscriptions.values.filter { $0.pid == session.pid }
        for subscription in targets {
            subscription.callback(event)
        }
    }

    func appSession(_ session: AppSession, didDiscoverWindow window: WindowInfo) {
        logger.info("[\(session.appIdentifier)] window discovered: #\(window.windowID) \"\(window.windowTitle)\" (\(window.role), \(window.bounds.width)x\(window.bounds.height))")
        logger.info("[\(session.appIdentifier)] window #\(window.windowID) parentWindowID: \(window.parentWindowID.map { "#\($0)" } ?? "nil")")

        // TODO: SkyLight Window Iterator를 사용한 윈도우 열거 (참고용)
        // guard let connection = SkyLightPrivate.SLSMainConnectionID?() else { return }
        // let query = SkyLightPrivate.SLSWindowQueryWindows?(connection, [CGWindowID(window.windowID)] as CFArray, 1)
        // guard let query, let iterator = SkyLightPrivate.SLSWindowQueryResultCopyWindows?(query) else { return }
        // while true {
        //     let result = SkyLightPrivate.SLSWindowIteratorAdvance?(iterator)
        //     guard result == .success else { break }
        //     let windowId = SkyLightPrivate.SLSWindowIteratorGetWindowID?(iterator) ?? 0
        //     let parentId = SkyLightPrivate.SLSWindowIteratorGetParentID?(iterator) ?? 0
        //     logger.info("[\(session.appIdentifier)] \(windowId) => \(parentId)")
        // }

        let event = WindowChangedEvent(
            eventType: .metadataChanged,
            windowID: window.windowID,
            info: window
        )
        dispatchWindowEvent(event)
    }

    func appSession(_ session: AppSession, didUpdateWindow window: WindowInfo) {
        logger.info("[\(session.appIdentifier)] window updated: #\(window.windowID) \"\(window.windowTitle)\" (\(window.bounds.x),\(window.bounds.y) \(window.bounds.width)x\(window.bounds.height))")

        // 통합 이벤트: 이동, 리사이즈, 메타 변경을 하나로 전달
        let event = WindowChangedEvent(
            eventType: [.moved, .resized, .metadataChanged],
            windowID: window.windowID,
            info: window
        )
        dispatchWindowEvent(event)
    }

    func appSession(_ session: AppSession, didCloseWindow windowID: WindowID) {
        logger.info("[\(session.appIdentifier)] window closed: #\(windowID)")
        let event = WindowChangedEvent(
            eventType: .closed,
            windowID: UInt64(windowID),
            info: nil
        )
        dispatchWindowEvent(event)
    }

    func appSession(_ session: AppSession, didChangeWindowFocusTo windowID: WindowID?) {
        logger.info("[\(session.appIdentifier)] window focus changed: \(windowID.map { "#\($0)" } ?? "none")")
        if let windowID {
            let window = session.monitoredWindows[windowID]
            let event = WindowChangedEvent(
                eventType: .focused,
                windowID: UInt64(windowID),
                info: window
            )
            dispatchWindowEvent(event)
        }
    }
}

// MARK: - WindowFilter Matching

extension WindowFilter {
    /// 윈도우 정보가 이 필터에 매칭되는지 평가
    func matches(_ window: WindowInfo) -> Bool {
        if let expression {
            return expression.matches(window)
        }

        if expressions.isEmpty {
            return true
        }

        switch `operator` {
        case .and:
            return expressions.allSatisfy { $0.matches(window) }
        case .or:
            return expressions.contains { $0.matches(window) }
        default:
            return true
        }
    }

    /// 필터에서 pid 값을 추출 (pid 기반 필터인 경우에만)
    func extractPIDs() -> Set<pid_t>? {
        if let expression {
            if case .pid(let pid) = expression.field {
                return [pid_t(pid)]
            }
            return nil
        }

        var pids = Set<pid_t>()
        for child in expressions {
            if let childPIDs = child.extractPIDs() {
                pids.formUnion(childPIDs)
            }
        }
        return pids.isEmpty ? nil : pids
    }
}

extension WindowFilterExpression {
    /// 윈도우 정보가 이 표현식에 매칭되는지 평가
    func matches(_ window: WindowInfo) -> Bool {
        let windowValue: String
        let filterValue: String

        switch field {
        case .windowID(let id):
            filterValue = "\(id)"
            windowValue = "\(window.windowID)"
        case .pid(let pid):
            filterValue = "\(pid)"
            windowValue = "\(window.pid)"
        case .windowTitle(let title):
            filterValue = title
            windowValue = window.windowTitle
        case .applicationName(let name):
            filterValue = name
            windowValue = window.applicationName
        case .applicationBundleID(let bundleID):
            filterValue = bundleID
            windowValue = window.applicationBundleID
        case .windowClass(let cls):
            filterValue = cls
            windowValue = window.windowClass
        }

        let result: Bool
        switch `operator` {
        case .matchExact:
            result = windowValue == filterValue
        case .matchContains:
            result = windowValue.contains(filterValue)
        case .matchIContains:
            result = windowValue.localizedCaseInsensitiveContains(filterValue)
        case .matchRegex:
            result = (try? NSRegularExpression(pattern: filterValue))
                .map { regex in
                    regex.firstMatch(in: windowValue, range: NSRange(windowValue.startIndex..., in: windowValue)) != nil
                } ?? false
        default:
            result = windowValue == filterValue
        }

        return invert ? !result : result
    }
}


extension WindowInfo {
    var isNSLocalWindowSharingWindow: Bool {
        self.role == .dialog &&
        ((self.bounds.width == 66 || self.bounds.width == 60) && self.bounds.height == 20)
    }
    
    var isStandaloneWindow: Bool {
        self.parentWindowID == nil || self.parentWindowID == 0
    }
}
