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

/// 디스플레이 구성이 변경될 때 알림을 제공하는 모니터입니다.
@MainActor
class DisplayLayoutManager: ObservableObject, CInteropHandle {
    static let shared = DisplayLayoutManager()

    let logger = NoctilucaLogger(category: "DisplayReconfigurationMonitor")

    @Published
    private(set) var displayLayouts: [CGDirectDisplayID: NSScreen] = [:]

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
    
    init() {
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

        for screen in NSScreen.screens {
            guard let displayID = screen.compatibleDisplayID else {
                logger.error("[WTF] updateDisplayLayoutsInner(): ???? why NSScreen.compatibleDisplayID is nil?")
                // TODO: capture event with sentry (when telemetry is enabled)
                continue
            }

            newLayouts[displayID] = screen
        }

        self.displayLayouts = newLayouts

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
