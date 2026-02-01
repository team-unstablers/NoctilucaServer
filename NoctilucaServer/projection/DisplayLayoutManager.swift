//
//  DisplayReconfigurationMonitor.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation
import Combine

import Cocoa
import CoreGraphics

import SiriusKit

final class ThreadSafeLayoutStorage: @unchecked Sendable {
    private var layouts: [CGDirectDisplayID: NOCScreen] = [:]
    private let lock = NSLock()
    
    func update(_ newLayouts: [CGDirectDisplayID: NOCScreen]) {
        lock.lock()
        defer { lock.unlock() }
        layouts = newLayouts
    }
    
    func get(_ displayID: CGDirectDisplayID) -> NOCScreen? {
        lock.lock()
        defer { lock.unlock() }
        return layouts[displayID]
    }
    
    func getAll() -> [CGDirectDisplayID: NOCScreen] {
        lock.lock()
        defer { lock.unlock() }
        return layouts
    }
}

enum DisplayLayoutManagerMonitoringState {
    case idle
    case monitoring
}

/// 디스플레이 변경 이벤트를 나타냅니다.
struct DisplayChangeEvent {
    let displayID: CGDirectDisplayID
    let eventType: DisplayChangeEventType
    let screen: NSScreen?
}

fileprivate func displayReconfigurationCallback(
    displayID: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags,
    userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo else {
        return
    }

    if flags.contains(.beginConfigurationFlag) {
        // Ignoring begin configuration event
        return
    }

    let monitor = DisplayLayoutManager.fromCInteropHandle(userInfo)

    Task { @MainActor in
        monitor.updateDisplayLayouts(displayID: displayID, flags: flags)
    }
}

/// '제정신인' 디스플레이 정보를 나타냅니다.
///
/// # 왜 '제정신'인가
///
/// NOCScreen은 X11 좌표계를 기준으로 계산됩니다.
/// - NOCScreen의 (0, 0)은 그냥 전체 뷰포트의 (0, 0)입니다. NSScreen의 (0, 0)은 메인 디스플레이의 좌측 상단입니다.
/// - NOCScreen의 y축은 아래로 증가합니다. 반면 NSScreen의 y축은 위로 증가합니다.
///
struct NOCScreen: Identifiable, Hashable, Equatable {
    /// 디스플레이 ID.
    let id: CGDirectDisplayID
    
    /// 디스플레이의 프레임.
    /// origin = 좌측 상단
    /// size = 디스플레이 해상도 (픽셀 단위)
    let frame: CGRect
    
    /// 디스플레이의 스케일 팩터 (@1x, @2x, ...)
    let scaleFactor: CGFloat
    
    init(id: CGDirectDisplayID, frame: CGRect, scaleFactor: CGFloat) {
        self.id = id
        self.frame = frame
        self.scaleFactor = scaleFactor
    }
    
    init?(from nsScreen: NSScreen, anchor mainScreen: NSScreen) {
        guard let displayID = nsScreen.compatibleDisplayID else {
            // fatalError("[WTF] NOCScreen.init(from:): NSScreen.compatibleDisplayID is nil")
            return nil
        }
        
        let nsFrame = nsScreen.frame
        let mainFrame = mainScreen.frame
        
        // NSScreen 좌표계를 NOCScreen 좌표계로 변환
        let nocOrigin = CGPoint(
            x: nsFrame.origin.x,
            y: mainFrame.size.height - (nsFrame.origin.y + nsFrame.size.height)
        )
       
        let nocFrame = CGRect(origin: nocOrigin, size: nsFrame.size)
        
        self.id = displayID
        self.frame = nocFrame
        self.scaleFactor = nsScreen.backingScaleFactor
    }
}

/// 디스플레이 구성이 변경될 때 알림을 제공하는 모니터입니다.
@MainActor
class DisplayLayoutManager: ObservableObject, CInteropHandle {
    nonisolated static let shared = DisplayLayoutManager()

    let logger = NoctilucaLogger(category: "DisplayReconfigurationMonitor")

    @Published
    private(set) var displayLayouts: [CGDirectDisplayID: NSScreen] = [: ]
    
    // TODO: 추후 displayLayouts을 얘가 잡아먹어야 함
    private(set) var nocDisplayLayouts: [CGDirectDisplayID: NOCScreen] = [:]

    nonisolated let layoutStorage = ThreadSafeLayoutStorage()

    @Published
    private(set) var monitoringState: DisplayLayoutManagerMonitoringState = .idle

    private var updateDisplayLayoutsTask: Task<Void, Never>? = nil

    /// 디바운스 중인 이벤트들을 저장합니다.
    private var pendingEvents: [(displayID: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags)] = []

    private let displayChangeSubject = PassthroughSubject<DisplayChangeEvent, Never>()

    /// 디스플레이 변경 이벤트를 발행하는 퍼블리셔입니다.
    /// 1초의 디바운스가 적용됩니다.
    var displayChangePublisher: AnyPublisher<DisplayChangeEvent, Never> {
        displayChangeSubject
            .debounce(for: .seconds(1.0), scheduler: RunLoop.main)
            .eraseToAnyPublisher()
    }

    /// 디바운스 없이 즉시 이벤트를 받는 퍼블리셔입니다.
    var displayChangePublisherImmediate: AnyPublisher<DisplayChangeEvent, Never> {
        displayChangeSubject.eraseToAnyPublisher()
    }
    
    nonisolated init() {
        self.logger.debug("new DisplayReconfigurationMonitor created")
    }
    
    deinit {
        CGDisplayRemoveReconfigurationCallback(
            displayReconfigurationCallback,
            self.asCInteropHandle
        )
    }
    
    func updateDisplayLayouts() {
        // debounce
        self.updateDisplayLayoutsTask?.cancel()

        self.updateDisplayLayoutsTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(1000))
                self.updateDisplayLayoutsInner()
            } catch {
                // pass
            }
        }
    }

    func updateDisplayLayouts(displayID: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        // 이벤트를 저장
        self.pendingEvents.append((displayID: displayID, flags: flags))

        // debounce
        self.updateDisplayLayoutsTask?.cancel()

        self.updateDisplayLayoutsTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(1000))
                self.updateDisplayLayoutsInner()
            } catch {
                // pass
            }
        }
    }

    private func updateDisplayLayoutsInner() {
        self.logger.info("updateDisplayLayouts(): updating display layouts...")

        let previousLayouts = self.displayLayouts
        var newLayouts: [CGDirectDisplayID: NSScreen] = [:]
        var newNocLayouts: [CGDirectDisplayID: NOCScreen] = [:]

        for screen in NSScreen.screens {
            guard let displayID = screen.compatibleDisplayID else {
                logger.error("[WTF] updateDisplayLayoutsInner(): ???? why NSScreen.compatibleDisplayID is nil?")
                // TODO: capture event with sentry (when telemetry is enabled)
                continue
            }

            newLayouts[displayID] = screen
            newNocLayouts[displayID] = NOCScreen(from: screen, anchor: NSScreen.main!)
        }

        self.displayLayouts    = newLayouts
        self.nocDisplayLayouts = newNocLayouts
        
        self.layoutStorage.update(newNocLayouts)

        // 이벤트 발행
        self.publishDisplayChangeEvents(previousLayouts: previousLayouts, newLayouts: newLayouts)
        self.pendingEvents.removeAll()
    }

    private func publishDisplayChangeEvents(
        previousLayouts: [CGDirectDisplayID: NSScreen],
        newLayouts: [CGDirectDisplayID: NSScreen]
    ) {
        // 대기 중인 이벤트가 없으면 전체 레이아웃 변경을 감지
        if pendingEvents.isEmpty {
            // 새로 연결된 디스플레이
            for (displayID, screen) in newLayouts where previousLayouts[displayID] == nil {
                let event = DisplayChangeEvent(
                    displayID: displayID,
                    eventType: .connected,
                    screen: screen
                )
                displayChangeSubject.send(event)
            }

            // 연결 해제된 디스플레이
            for displayID in previousLayouts.keys where newLayouts[displayID] == nil {
                let event = DisplayChangeEvent(
                    displayID: displayID,
                    eventType: .disconnected,
                    screen: nil
                )
                displayChangeSubject.send(event)
            }
            return
        }

        // 대기 중인 이벤트들을 처리
        var processedDisplayIDs = Set<CGDirectDisplayID>()

        for (displayID, flags) in pendingEvents {
            // 이미 처리한 디스플레이는 스킵
            guard !processedDisplayIDs.contains(displayID) else {
                continue
            }
            processedDisplayIDs.insert(displayID)

            let eventType = self.eventTypeFromFlags(flags)
            let screen = newLayouts[displayID]

            let event = DisplayChangeEvent(
                displayID: displayID,
                eventType: eventType,
                screen: screen
            )

            self.logger.debug("publishDisplayChangeEvents(): displayID=\(displayID), eventType=\(eventType)")
            displayChangeSubject.send(event)
        }
    }

    private func eventTypeFromFlags(_ flags: CGDisplayChangeSummaryFlags) -> DisplayChangeEventType {
        var eventType: DisplayChangeEventType = []

        if flags.contains(.addFlag) {
            eventType.insert(.connected)
        }
        if flags.contains(.removeFlag) {
            eventType.insert(.disconnected)
        }
        if flags.contains(.movedFlag) || flags.contains(.setModeFlag) || flags.contains(.setMainFlag) {
            eventType.insert(.modified)
        }
        if flags.contains(.setMainFlag) {
            eventType.insert(.becamePrimary)
        }

        // 플래그가 비어있으면 modified로 처리
        if eventType.isEmpty {
            eventType = .modified
        }

        return eventType
    }
    
    func startMonitoring() {
        self.logger.debug("startMonitoring(): registering display reconfiguration callback...")
        
        let retval = CGDisplayRegisterReconfigurationCallback(displayReconfigurationCallback, self.asCInteropHandle)
        
        guard retval == .success else {
            self.logger.error("startMonitoring(): failed to register display reconfiguration callback: \(retval)")
            return
        }
        
        self.monitoringState = .monitoring
    }
    
    func stopMonitoring() {
        self.logger.debug("stopMonitoring(): removing display reconfiguration callback...")
        
        let retval = CGDisplayRemoveReconfigurationCallback(displayReconfigurationCallback, self.asCInteropHandle)
        
        defer {
            self.monitoringState = .idle
        }
        
        guard retval == .success else {
            self.logger.error("stopMonitoring(): failed to remove display reconfiguration callback: \(retval)")
            return
        }
    }
}

extension DisplayLayoutManager {
    /// 주어진 디스플레이 ID와 퍼센트 좌표를 기반으로 X11(Global Top-Left) 좌표계의 절대 좌표를 반환합니다.
    nonisolated func globalPoint(fromPercent point: CGPoint, on displayID: CGDirectDisplayID) -> CGPoint? {
        guard let screen = self.layoutStorage.get(displayID) else { return nil }
        
        let x = screen.frame.origin.x + (screen.frame.width * point.x)
        let y = screen.frame.origin.y + (screen.frame.height * point.y)
        
        return CGPoint(x: x, y: y)
    }

    /// NSEvent를 통해 취득한 마우스 커서의 위치의 좌표계를 X11 좌표계로 변환합니다.
    nonisolated static func resolveX11CursorPosition(_ position: CGPoint) -> CGPoint {
        guard let mainScreen = NSScreen.main else {
            return position
        }
        
        let mainFrame = mainScreen.frame
        
        let x11Position = CGPoint(
            x: position.x,
            y: mainFrame.size.height - position.y
        )
        
        return x11Position
    }
    
    
    /// 주어진 전체 디스플레이 좌표계의 좌표에 대해 해당하는 디스플레이와 상대 좌표를 반환합니다.
    /// Note: X11 좌표계를 기대합니다
    nonisolated func resolveRelativePoint(point: CGPoint) -> (CGDirectDisplayID, CGPoint)? {
        // Thread-safe access via layoutStorage
        // We need to iterate over all layouts to find the containing frame
        // This is a bit inefficient but safe.
        // Since ThreadSafeLayoutStorage doesn't expose iteration, we might need to add it or expose the dictionary copy.
        // For now, let's assume get() is not enough.
        
        // Let's modify ThreadSafeLayoutStorage to support iteration or getting all layouts.
        let layouts = self.layoutStorage.getAll()
        
        guard let entry = layouts.first(where: { $0.value.frame.contains(point) }) else {
            return nil
        }
        
        let displayID = entry.key
        let rect = entry.value.frame
        
        let relativePoint = CGPoint(
            x: point.x - rect.origin.x,
            y: point.y - rect.origin.y
        )
        
        return (displayID, relativePoint)
    }
}
