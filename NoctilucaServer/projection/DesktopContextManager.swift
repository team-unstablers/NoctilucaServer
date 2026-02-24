//
//  DesktopContextManager.swift
//  NoctilucaServer
//

import Foundation
import CoreGraphics
import ApplicationServices // For AXUIElement
import AppKit
import Combine

import SiriusKit

// MARK: - Core Types

let kAXWindowNumberAttribute = "AXWindowNumber"

typealias WindowID = CGWindowID

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

// 메뉴 구조는 재귀적이므로 간결하게 정의
struct AppMenuNode {
    let title: String
    let isEnabled: Bool
    let shortcut: String?
    let children: [AppMenuNode]? // nil이면 Leaf node (Action)
    
    // 실행을 위한 식별자 (AXUIElement 등)
    let actionIdentifier: Any?
}

// MARK: - Errors

enum DesktopContextError: Error {
    case accessibilityPermissionMissing
    case cannotCreateAXObserver(AXError)
    case windowNotFound(WindowID)
    case appNotRunning
    case invalidWindowFrame
    case failedToSetFocusedWindow(AXError)
    case failedToPerformAction(String, AXError)
    case failedToUpdateWindowFrame(AXError)
    case failedToReadAttribute(String, AXError)
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
    
    // Menu
    func appSessionDidUpdateMenu(_ session: AppSession, menu: AppMenuNode)
    
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

    private nonisolated let observedNotifications: [CFString] = [
        kAXWindowCreatedNotification as CFString,
        kAXUIElementDestroyedNotification as CFString,
        kAXFocusedWindowChangedNotification as CFString,
        kAXMainWindowChangedNotification as CFString,
        kAXWindowMovedNotification as CFString,
        kAXWindowResizedNotification as CFString,
        kAXTitleChangedNotification as CFString
    ]

    // 디바운스+병합: 잦은 AX 노티를 100~200ms 간격으로 묶고, 실행 중 중복을 한 번으로 합친다.
    private let refreshSubject = PassthroughSubject<Void, Never>()
    private var cancellables = Set<AnyCancellable>()
    private let refreshDelay: TimeInterval = 0.15
    private var isRefreshing = false
    private var pendingRefresh = false
    private var isStopped = false
    
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
    
    /// AXObserver 콜백 등에서 호출되어 Delegate에게 알림
    private func handleAXNotification(_ notification: CFString) {
        _ = notification // 현재는 이벤트 유형별 분기를 하지 않지만, 구분을 위해 보존
        refreshSubject.send(())
    }
    
    private func setupObserver() throws {
        var observer: AXObserver?
        let result = AXObserverCreate(self.pid, { _, _, notification, context in
            guard let context else { return }
            // AXObserver 콜백은 메인 런루프에서 실행되므로 assumeIsolated가 안전함
            MainActor.assumeIsolated {
                let session = Unmanaged<AppSession>.fromOpaque(context).takeUnretainedValue()
                session.handleAXNotification(notification)
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
            print(element)
            
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
            
            var hints: WindowHint = [
                .hasShadow,
                .hasTransparency,
            ]
            var flags: WindowInfoFlags = []
            
            if isActive {
                flags.insert(.isFocused)
            }
            
            if !isVisible || !isOnscreen {
                flags.insert(.isHidden)
            }
            
            return (windowID, WindowInfo(
                windowID: UInt64(windowID),
                pid: UInt64(ownerPID),
                windowTitle: title,
                applicationName: runningApplication.localizedName ?? "(unknown)",
                applicationBundleID: runningApplication.bundleIdentifier ?? "app.noctiluca.server.UnknownBundleID",
                windowClass: runningApplication.bundleIdentifier ?? "app.noctiluca.server.UnknownBundleID",
                role: .normal, // FIXME
                bounds: SRRect(x: bounds.origin.x, y: bounds.origin.y, width: bounds.size.width, height: bounds.size.height),
                iconHash: nil, // TODO
                thumbnail: nil, // TODO
                metadata: [
                    "app.noctiluca.server.x-window-layer": "\(layer)",
                    "app.noctiluca.server.x-window-alpha": "\(alpha)"
                ],
                hints: hints, // TODO
                flags: flags // TODO
            ))
        })
    }
}

/// 시스템 전체의 앱 실행 상태와 포커스를 관장하는 매니저
/// (기존 WindowManagerOrSpy)
@MainActor
final class DesktopContextManager {
    public static let shared = DesktopContextManager()
    
    weak var delegate: DesktopContextManagerDelegate?
    
    /// 현재 감시 중인 앱 세션들 (PID: Session)
    private(set) var activeSessions: [pid_t: AppSession] = [:]
    
    private let workspace: NSWorkspace
    private var workspaceObservers: [Any] = []
    
    nonisolated init(workspace: NSWorkspace = .shared) {
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
        for session in activeSessions.values {
            session.stop()
        }
        activeSessions.removeAll()
        workspaceObservers.forEach { observer in
            workspace.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }
    
    // MARK: - Global Window Queries
    // winman.proto의 WindowListRequest 처리를 위해 필요할 수 있음
    
    /// 현재 화면에 있는 모든 윈도우 리스트 조회 (CGWindowList 활용)
    func globalWindowList() -> [WindowInfo] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let infoList = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let runningApps = self.runningApplications()
        let frontmostWindowID = infoList.compactMap { $0[kCGWindowNumber as String] as? CGWindowID }.first

        return infoList.compactMap { info in
            guard info.keys.contains(kCGWindowBounds as String) else {
                return nil
            }

            let boundsDictionary = info[kCGWindowBounds as String] as! CFDictionary
            guard let bounds = CGRect(dictionaryRepresentation: boundsDictionary) else {
                return nil
            }
            
            let relatedApp = runningApps.first { app in
                guard let pid = info[kCGWindowOwnerPID as String] as? pid_t else { return false }
                return app.processIdentifier == pid
            }

            let windowID = info[kCGWindowNumber as String] as? CGWindowID ?? 0
            let layer = Int32(info[kCGWindowLayer as String] as? Int ?? 0)
            let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            let title = info[kCGWindowName as String] as? String ?? ""
            let isOnscreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false
            let alpha = info[kCGWindowAlpha as String] as? Double ?? 0.0
            let isVisible = isOnscreen && alpha > 0.01
            let isActive = frontmostWindowID == windowID
            
            var hints: WindowHint = [
                .hasShadow,
                .hasTransparency,
            ]
            var flags: WindowInfoFlags = []
            
            if isActive {
                flags.insert(.isFocused)
            }
            
            if !isVisible || !isOnscreen {
                flags.insert(.isHidden)
            }
            
            return WindowInfo(
                windowID: UInt64(windowID),
                pid: UInt64(ownerPID),
                windowTitle: title,
                applicationName: relatedApp?.localizedName ?? "(unknown)",
                applicationBundleID: relatedApp?.bundleIdentifier ?? "app.noctiluca.server.UnknownBundleID",
                windowClass: relatedApp?.bundleIdentifier ?? "app.noctiluca.server.UnknownBundleID",
                role: .normal, // FIXME
                bounds: SRRect(x: bounds.origin.x, y: bounds.origin.y, width: bounds.size.width, height: bounds.size.height),
                iconHash: nil, // TODO
                thumbnail: nil, // TODO
                metadata: [
                    "app.noctiluca.server.x-window-layer": "\(layer)",
                    "app.noctiluca.server.x-window-alpha": "\(alpha)"
                ],
                hints: hints, // TODO
                flags: flags // TODO
            )
        }
    }
    
    // MARK: - Private
    
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
                self.delegate?.desktopManager(self, didDetectAppLaunch: app)
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
                if let session = self.activeSessions[app.processIdentifier] {
                    session.delegate?.appSessionDidTerminate(session)
                }
                self.stopMonitoring(pid: app.processIdentifier)
                self.delegate?.desktopManager(self, didDetectAppTermination: app.processIdentifier)
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
                self.delegate?.desktopManager(self, didChangeFrontmostApp: app ?? self.workspace.frontmostApplication)
            }
        }
        
        self.workspaceObservers.append(contentsOf: [launchObserver, terminationObserver, activationObserver])
    }
    
    private func shouldMonitor(_ app: NSRunningApplication) -> Bool {
        guard app.isTerminated == false else { return false }
        return app.activationPolicy != .prohibited
    }
}
