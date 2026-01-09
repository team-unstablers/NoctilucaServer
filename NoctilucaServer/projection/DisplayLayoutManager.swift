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
    
    private func updateDisplayLayoutsInner() {
        self.logger.info("updateDisplayLayouts(): updating display layouts...")
        
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
