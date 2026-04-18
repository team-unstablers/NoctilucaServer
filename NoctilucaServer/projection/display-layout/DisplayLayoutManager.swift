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

fileprivate extension CGDisplayChangeSummaryFlags {
    var asSiriusEventType: DisplayChangeEventType {
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
        monitor.updateDisplayLayouts()

        monitor.publishDisplayChangeEvent(DisplayChangeEvent(
            displayID: displayID,
            eventType: flags.asSiriusEventType,
            screen: NSScreen.screens.first { $0.compatibleDisplayID == displayID }
        ))
    }
}

enum DisplayLayoutManagerError: Error, Sendable {
    case unknownError
    case displaySpecNotCompatible
    case displaySpecApplyFailure(CGError?)
}

/// 디스플레이 구성이 변경될 때 알림을 제공하는 모니터입니다.
@MainActor
final class DisplayLayoutManager: ObservableObject, CInteropHandle, Sendable {
    nonisolated(unsafe) static let shared = DisplayLayoutManager()

    let logger = NoctilucaLogger(category: "DisplayReconfigurationMonitor")

    @Published
    private(set) var globalFrame: CGRect = .zero
    @Published
    private(set) var intermediateGlobalFrame: CGRect = .zero
    
    let displayLayouts = ConcurrentDictionary<CGDirectDisplayID, NOCScreen>()

    let displayChangeSubject = PassthroughSubject<DisplayChangeEvent, Never>()
    let displayLayoutChangeSubject = PassthroughSubject<[CGDirectDisplayID: NOCScreen], Never>()

    let virtualDisplayManager = VirtualDisplayManager()

    @Published
    private(set) var monitoringState: DisplayLayoutManagerMonitoringState = .idle

    private var updateDisplayLayoutsTask: Task<Void, Never>? = nil

    /// 전송 대기 이벤트
    private var pendingEvents: [DisplayChangeEvent] = []
    
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
                
                for event in pendingEvents {
                    displayChangeSubject.send(event)
                }
                
                pendingEvents.removeAll()
                displayLayoutChangeSubject.send(displayLayouts.snapshot())
            } catch {
                // cancelled
            }
        }
    }
    
    @MainActor
    private func updateDisplayLayoutsInner() {
        self.logger.info("updateDisplayLayouts(): updating display layouts...")
        var newLayouts: [CGDirectDisplayID: NOCScreen] = [:]
        
        let intermediateGlobalFrame = NOCScreen.produceIntermediateGlobalFrame(from: NSScreen.screens)
        let globalFrame = NOCScreen.produceGlobalFrame(from: NSScreen.screens)

        for screen in NSScreen.screens {
            guard let displayID = screen.compatibleDisplayID else {
                logger.error("[WTF] updateDisplayLayoutsInner(): ???? why NSScreen.compatibleDisplayID is nil?")
                // TODO: capture event with sentry (when telemetry is enabled)
                continue
            }

            newLayouts[displayID] = NOCScreen(from: screen, intermediateGlobalFrame: intermediateGlobalFrame)
        }

        self.displayLayouts.replaceSnapshot(newLayouts)
        self.intermediateGlobalFrame = intermediateGlobalFrame
        self.globalFrame = globalFrame
    }
    
    @MainActor
    fileprivate func publishDisplayChangeEvent(_ event: DisplayChangeEvent) {
        pendingEvents.append(consume event)
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

        Task { [virtualDisplayManager] in
            await virtualDisplayManager.shutdown()
        }

        defer {
            self.monitoringState = .idle
        }

        guard retval == .success else {
            self.logger.error("stopMonitoring(): failed to remove display reconfiguration callback: \(retval)")
            return
        }
    }
}

