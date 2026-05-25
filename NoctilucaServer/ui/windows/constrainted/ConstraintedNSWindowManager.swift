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
    
    // @MainActor
    deinit {
        // FIXME: Swift 컴파일러가 크래시함
        // self.shutdown()
    }
    
    func startup() {
        guard self.subscription == nil else {
            return
        }
        
        self.subscription = displayLayoutManager.displayLayoutChangeSubject
            .debounce(for: .milliseconds(1000), scheduler: DispatchQueue.main)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot in
                self?.updateWindows(for: snapshot)
            }
        
        self.updateWindows(for: displayLayoutManager.displayLayouts.snapshot())
    }
    
    func shutdown() {
        self.subscription?.cancel()
        self.subscription = nil

        for (displayID, window) in windows {
            self.logger.debug("Closing \(Window.self) for displayID: \(displayID) (shutdown)")
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }
    
    /// 지정된 디스플레이에 대한 윈도우를 반환합니다.
    /// 윈도우가 아직 생성되지 않았다면 최대 `timeout`까지 대기합니다.
    func window(for displayID: CGDirectDisplayID, timeout: Duration = .seconds(3)) async -> Window? {
        if let window = windows[displayID] {
            return window
        }

        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            if let window = windows[displayID] {
                return window
            }
        }

        self.logger.warning("window(for:timeout:): timed out waiting for \(Window.self) for displayID: \(displayID)")
        return nil
    }

    func updateWindows(for displayLayouts: [CGDirectDisplayID: NOCScreen]) {
        // 1. Remove windows for disconnected displays
        let currentDisplayIDs = Set(displayLayouts.keys)
        let existingDisplayIDs = Set(windows.keys)
        
        let disconnectedDisplayIDs = existingDisplayIDs.subtracting(currentDisplayIDs)
        for displayID in disconnectedDisplayIDs {
            if let window = windows.removeValue(forKey: displayID) {
                self.logger.debug("Closing \(Window.self) for disconnected displayID: \(displayID)")
                window.orderOut(nil)
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


