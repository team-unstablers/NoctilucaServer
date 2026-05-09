//
//  LocalDisplayLayoutManager.swift
//  NoctilucaClient (macOS only)
//
//  AppStream 시 클라이언트 자신의 NSScreen 레이아웃을 호스트 가상 디스플레이로
//  복제하기 위해, 로컬 디스플레이 변경을 감시한다.
//  서버 측 `NoctilucaServer/projection/display-layout/DisplayLayoutManager.swift`
//  를 클라이언트용으로 단순화한 이식체이며, 가상 디스플레이 spawning 인프라는
//  포함하지 않는다 (관찰 전용).
//

#if os(macOS)

import Foundation
import Combine

import Cocoa
import CoreGraphics

import SiriusKitCore

/// 로컬 디스플레이 변경 이벤트.
struct LocalDisplayChangeEvent: Sendable {
    let displayID: CGDirectDisplayID
    let eventType: EventType
    let screen: LocalScreenInfo?

    enum EventType: Sendable {
        case connected
        case disconnected
        case becamePrimary
        case modified
    }
}

/// 클라이언트 측 NSScreen 의 단일 스냅샷.
///
/// `frame` 은 macOS Cocoa 좌표계 (bottom-left origin) 의 글로벌 좌표.
/// `x11Frame` 은 호스트로 보낼 때 사용하는 top-left 좌표 (전체 NSScreen.screens 의 maxY 를 기준으로 flip).
/// 두 좌표계 간 변환 유틸은 `convertX11ToCocoa(_:in:)` / `convertCocoaToX11(_:)` 사용.
struct LocalScreenInfo: Sendable {
    let displayID: CGDirectDisplayID
    let frame: CGRect              // Cocoa (bottom-left origin)
    let x11Frame: CGRect           // top-left origin, NSScreen.screens 전체 기준 flip
    let resolution: CGSize         // physical pixels
    let scaleFactor: CGFloat
    let refreshRate: Double
    let isPrimary: Bool
}

extension NSScreen {
    /// 서버 측 동등 extension 의 클라용 복사. macOS 26+ 에서는 `cgDirectDisplayID`,
    /// 그 이하에서는 `deviceDescription[NSScreenNumber]` 로 displayID 조회.
    var compatibleDisplayID: CGDirectDisplayID? {
        if #available(macOS 26.0, *) {
            return self.cgDirectDisplayID
        } else {
            return deviceDescription[.init("NSScreenNumber")] as? CGDirectDisplayID
        }
    }
}

fileprivate extension CGDisplayChangeSummaryFlags {
    var asLocalEventType: LocalDisplayChangeEvent.EventType {
        if self.contains(.addFlag) || self.contains(.enabledFlag) {
            return .connected
        }
        if self.contains(.removeFlag) || self.contains(.disabledFlag) {
            return .disconnected
        }
        if self.contains(.setMainFlag) {
            return .becamePrimary
        }
        return .modified
    }
}

fileprivate func localDisplayReconfigurationCallback(
    displayID: CGDirectDisplayID,
    flags: CGDisplayChangeSummaryFlags,
    userInfo: UnsafeMutableRawPointer?
) {
    guard let userInfo else { return }

    if flags.contains(.beginConfigurationFlag) {
        return
    }

    let monitor = LocalDisplayLayoutManager.fromCInteropHandle(userInfo)

    Task { @MainActor in
        monitor.scheduleUpdate(displayID: displayID, flags: flags)
    }
}

@MainActor
final class LocalDisplayLayoutManager: ObservableObject, CInteropHandle, Sendable {
    nonisolated(unsafe) static let shared = LocalDisplayLayoutManager()

    let logger = NoctilucaLogger(category: "LocalDisplayLayoutManager")

    /// 현재 알려진 디스플레이 레이아웃 스냅샷.
    @Published
    private(set) var displayLayouts: [CGDirectDisplayID: LocalScreenInfo] = [:]

    /// 디스플레이별 변경 이벤트 (1초 debounce 후 일괄 발행).
    let displayChangeSubject = PassthroughSubject<LocalDisplayChangeEvent, Never>()

    /// 전체 레이아웃 스냅샷이 갱신되었을 때 발행.
    let displayLayoutChangeSubject = PassthroughSubject<[CGDirectDisplayID: LocalScreenInfo], Never>()

    private enum MonitoringState {
        case idle
        case monitoring
    }

    private var monitoringState: MonitoringState = .idle
    private var updateTask: Task<Void, Never>? = nil
    private var pendingEvents: [LocalDisplayChangeEvent] = []

    nonisolated init() {
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(
            localDisplayReconfigurationCallback,
            self.asCInteropHandle
        )
    }

    // MARK: - Lifecycle

    func startMonitoring() {
        guard monitoringState == .idle else { return }
        let retval = CGDisplayRegisterReconfigurationCallback(
            localDisplayReconfigurationCallback,
            self.asCInteropHandle
        )
        guard retval == .success else {
            logger.error("startMonitoring(): CGDisplayRegisterReconfigurationCallback failed: \(retval.rawValue)")
            return
        }
        monitoringState = .monitoring
        rebuildLayouts()
    }

    func stopMonitoring() {
        guard monitoringState == .monitoring else { return }
        let retval = CGDisplayRemoveReconfigurationCallback(
            localDisplayReconfigurationCallback,
            self.asCInteropHandle
        )
        if retval != .success {
            logger.warning("stopMonitoring(): CGDisplayRemoveReconfigurationCallback failed: \(retval.rawValue)")
        }
        updateTask?.cancel()
        updateTask = nil
        pendingEvents.removeAll()
        monitoringState = .idle
    }

    /// 현재 NSScreen.screens 를 즉시 스캔해 displayLayouts 를 채운다 (구독자에게 발행 없음).
    /// AppStream 시작 시점에 최신 스냅샷이 필요할 때 사용.
    @discardableResult
    func snapshot() -> [CGDirectDisplayID: LocalScreenInfo] {
        rebuildLayouts(silent: true)
        return displayLayouts
    }

    // MARK: - Internal

    fileprivate func scheduleUpdate(
        displayID: CGDirectDisplayID,
        flags: CGDisplayChangeSummaryFlags
    ) {
        let event = LocalDisplayChangeEvent(
            displayID: displayID,
            eventType: flags.asLocalEventType,
            screen: nil // 갱신 후 채움
        )
        pendingEvents.append(event)

        updateTask?.cancel()
        updateTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1000))
            guard !Task.isCancelled else { return }

            self.rebuildLayouts(silent: false)

            // pendingEvents 의 screen 필드를 갱신 후 발행.
            for pending in self.pendingEvents {
                let resolved = LocalDisplayChangeEvent(
                    displayID: pending.displayID,
                    eventType: pending.eventType,
                    screen: self.displayLayouts[pending.displayID]
                )
                self.displayChangeSubject.send(resolved)
            }
            self.pendingEvents.removeAll()
            self.displayLayoutChangeSubject.send(self.displayLayouts)
        }
    }

    @discardableResult
    private func rebuildLayouts(silent: Bool = false) -> [CGDirectDisplayID: LocalScreenInfo] {
        let screens = NSScreen.screens
        let mainID = CGMainDisplayID()

        // X11 변환의 기준이 되는 maxY (전체 화면 영역의 top edge in Cocoa coords).
        let allMaxY = screens.map { $0.frame.maxY }.max() ?? 0

        var newLayouts: [CGDirectDisplayID: LocalScreenInfo] = [:]
        for screen in screens {
            guard let displayID = screen.compatibleDisplayID else {
                logger.warning("rebuildLayouts: NSScreen without compatibleDisplayID; skipping")
                continue
            }

            let cocoaFrame = screen.frame
            let x11Origin = CGPoint(
                x: cocoaFrame.origin.x,
                y: allMaxY - cocoaFrame.maxY
            )
            let x11Frame = CGRect(origin: x11Origin, size: cocoaFrame.size)

            let scaleFactor = screen.backingScaleFactor
            let resolution = CGSize(
                width: cocoaFrame.width * scaleFactor,
                height: cocoaFrame.height * scaleFactor
            )

            let refreshRate = (screen.maximumRefreshInterval > 0)
                ? 1.0 / screen.maximumRefreshInterval
                : 60.0

            newLayouts[displayID] = LocalScreenInfo(
                displayID: displayID,
                frame: cocoaFrame,
                x11Frame: x11Frame,
                resolution: resolution,
                scaleFactor: scaleFactor,
                refreshRate: refreshRate,
                isPrimary: displayID == mainID
            )
        }

        displayLayouts = newLayouts
        if !silent {
            logger.info("rebuildLayouts: \(newLayouts.count) display(s); primary=\(mainID)")
        }
        return newLayouts
    }
}

// MARK: - Coordinate Conversion Utils

extension LocalDisplayLayoutManager {
    /// 호스트의 top-left global 좌표를 받아서, 매핑된 클라 NSScreen 안의 NSWindow
    /// origin (Cocoa bottom-left) 으로 변환한다.
    ///
    /// - Parameters:
    ///   - hostTopLeftOrigin: 윈도우의 호스트 글로벌 좌표 (top-left, `WindowInfo.bounds.origin`)
    ///   - windowSize: NSWindow 의 frame size (높이가 필요)
    ///   - hostVDFrame: 그 윈도우가 속한 호스트 VD 의 글로벌 frame (top-left)
    ///   - clientScreen: 매핑된 클라 NSScreen
    /// - Returns: NSWindow.setFrameOrigin 에 넘길 Cocoa 좌표
    static func translateToClientCocoa(
        hostTopLeftOrigin: CGPoint,
        windowSize: CGSize,
        hostVDFrame: CGRect,
        clientScreen: NSScreen
    ) -> CGPoint {
        // VD 내부의 top-left 좌표 (호스트 VD origin 을 빼서 정규화).
        let intra = CGPoint(
            x: hostTopLeftOrigin.x - hostVDFrame.origin.x,
            y: hostTopLeftOrigin.y - hostVDFrame.origin.y
        )

        // 클라 NSScreen 안의 Cocoa 좌표 (bottom-left).
        let cocoaX = clientScreen.frame.origin.x + intra.x
        let cocoaY = clientScreen.frame.maxY - intra.y - windowSize.height

        return CGPoint(x: cocoaX, y: cocoaY)
    }
}

#endif
