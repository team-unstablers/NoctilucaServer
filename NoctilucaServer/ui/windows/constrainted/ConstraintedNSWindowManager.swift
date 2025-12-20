//
//  DummyWindowManager.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/21/25.
//

import Foundation

import CoreGraphics
import Cocoa

import Combine

import SiriusKit

/// 디스플레이 변화를 감시하면서 각 디스플레이에 '제약된 윈도우'를 관리합니다.
class ConstraintedNSWindowManager<Window: NSWindow> where Window: ConstraintedNSWindow {
    private let logger = NoctilucaLogger(category: "ConstraintedNSWindowManager<\(Window.self)>")
    
    private let displayLayoutManager = DisplayLayoutManager.shared
    private var subscription: AnyCancellable? = nil
    
    private(set) var windows: [CGDirectDisplayID: Window] = [:]
    
    func startup() {
        guard self.subscription == nil else {
            return
        }
        
        self.subscription = displayLayoutManager.$displayLayouts
            .sink { [weak self] displayLayouts in
                self?.updateWindows(for: displayLayouts)
            }
        
        self.updateWindows(for: displayLayoutManager.displayLayouts)
    }
    
    func shutdown() {
        self.subscription?.cancel()
        self.subscription = nil
    }
    
    func updateWindows(for displayLayouts: [CGDirectDisplayID: CGRect]) {
        DispatchQueue.main.async {
            self.updateWindowsInner(for: displayLayouts)
        }
    }
    
    func updateWindowsInner(for displayLayouts: [CGDirectDisplayID: CGRect]) {
        // 1. Remove windows for disconnected displays
        let currentDisplayIDs = Set(displayLayouts.keys)
        let existingDisplayIDs = Set(windows.keys)
        
        let disconnectedDisplayIDs = existingDisplayIDs.subtracting(currentDisplayIDs)
        for displayID in disconnectedDisplayIDs {
            if let window = windows[displayID] {
                self.logger.debug("Closing \(Window.self) for disconnected displayID: \(displayID)")
                window.close()
                windows.removeValue(forKey: displayID)
            }
        }
        
        // 2. Add windows for newly connected displays
        let newDisplayIDs = currentDisplayIDs.subtracting(existingDisplayIDs)
        for displayID in newDisplayIDs {
            if let screen = NSScreen.screens.first(where: { $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID == displayID }) {
                self.logger.debug("Creating new \(Window.self) for displayID: \(displayID)")
                let window = Window(to: screen)
                
                windows[displayID] = window
            }
        }
    }
}



