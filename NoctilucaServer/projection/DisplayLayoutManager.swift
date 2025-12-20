//
//  DisplayReconfigurationMonitor.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

import CoreGraphics

import Combine

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
    
    if flags == .beginConfigurationFlag {
        // Ignoring begin configuration event
        return
    }
    
    let monitor = DisplayLayoutManager.fromCInteropHandle(userInfo)
    monitor.updateDisplayLayouts()
}


/// 디스플레이 구성이 변경될 때 알림을 제공하는 모니터입니다.
class DisplayLayoutManager: ObservableObject, CInteropHandle {
    static let shared = DisplayLayoutManager()
    
    let logger = NoctilucaLogger(category: "DisplayReconfigurationMonitor")
    
    @Published
    private(set) var displayLayouts: [CGDirectDisplayID: CGRect] = [:]
    
    @Published
    private(set) var monitoringState: DisplayLayoutManagerMonitoringState = .idle
    
    init() {
        self.logger.debug("new DisplayReconfigurationMonitor created")
    }
    
    deinit {
        self.stopMonitoring()
    }
    
    func updateDisplayLayouts() {
        DispatchQueue.main.async {
            self.updateDisplayLayoutsInner()
        }
    }
    
    private func updateDisplayLayoutsInner() {
        var displayCount: UInt32 = 0
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: 16)
        
        self.logger.info("updateDisplayLayouts(): updating display layouts...")
        
        let error = CGGetActiveDisplayList(UInt32(activeDisplays.count), &activeDisplays, &displayCount)
        
        guard error == .success else {
            self.logger.error("updateDisplayLayouts(): failed to get active display list: \(error)")
            return
        }
        
        var newLayouts: [CGDirectDisplayID: CGRect] = [:]
        
        for i in 0..<Int(displayCount) {
            let displayID = activeDisplays[i]
            let bounds = CGDisplayBounds(displayID)
            newLayouts[displayID] = bounds
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

