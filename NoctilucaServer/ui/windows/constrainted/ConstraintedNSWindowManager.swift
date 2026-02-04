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
@MainActor
class ConstraintedNSWindowManager<Window: NSWindow> where Window: ConstraintedNSWindow {
    private let logger = NoctilucaLogger(category: "ConstraintedNSWindowManager<\(Window.self)>")
    
    private let displayLayoutManager = DisplayLayoutManager.shared
    private var subscription: AnyCancellable? = nil
    
    private(set) var windows: [CGDirectDisplayID: Window] = [:]
    
    func startup() {
        guard self.subscription == nil else {
            return
        }
        
        self.subscription = displayLayoutManager.displayLayoutChangeSubject
            .debounce(for: .milliseconds(1000), scheduler: RunLoop.main)
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                self?.updateWindows(for: snapshot)
            }
        
        self.updateWindows(for: displayLayoutManager.displayLayouts.snapshot())
    }
    
    func shutdown() {
        self.subscription?.cancel()
        self.subscription = nil
    }
    
    func updateWindows(for displayLayouts: [CGDirectDisplayID: NOCScreen]) {
        // 1. Remove windows for disconnected displays
        let currentDisplayIDs = Set(displayLayouts.keys)
        let existingDisplayIDs = Set(windows.keys)
        
        let disconnectedDisplayIDs = existingDisplayIDs.subtracting(currentDisplayIDs)
        for displayID in disconnectedDisplayIDs {
            if let window = windows.removeValue(forKey: displayID) {
                self.logger.debug("Closing \(Window.self) for disconnected displayID: \(displayID)")
                window.close()
            }
        }
        
        // 2. Add windows for newly connected displays
        let newDisplayIDs = currentDisplayIDs.subtracting(existingDisplayIDs)
        for displayID in newDisplayIDs {
            guard let screen = displayLayouts[displayID] else {
                continue
            }
            
            if screen.frame.width <= 1 || screen.frame.height <= 1 {
                self.logger.warning("updateWindows(): invalid screen size for displayID: \(displayID) frame: \(screen.frame)")
                continue
            }
            
            self.logger.debug("Creating new \(Window.self) for displayID: \(displayID)")
            
            let window = Window(to: screen)
            windows[displayID] = window
        }
    }
}


