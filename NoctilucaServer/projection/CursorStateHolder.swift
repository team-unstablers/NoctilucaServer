//
//  CursorStateHolder.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/19/26.
//

import Foundation
import Combine

import AppKit

import SiriusKit

@MainActor
class CursorStateHolder: ObservableObject {
    static let shared = CursorStateHolder()
    
    let logger = NoctilucaLogger(category: "CursorStateHolder")
    
    @Published
    private(set) var cursorHash: Int = 0
    private(set) var cursorImage: NSImage? = nil
    private(set) var cursorHotspot: NSPoint? = nil
    
    @Published
    private(set) var cursorPosition: CGPoint = .zero
    
    private var observerToken: Any? = nil
    
    init() {
        do {
            try CoreGraphicsPrivate.open()
        } catch {
            logger.error("failed to load CoreGraphics library")
        }
        
        self.startObserveCursorEvent()
        self.updateCursorPosition()
        self.updateCursorHash()
    }
    
    @MainActor
    deinit {
        self.stopObserveCursorEvent()
    }
    
    private func startObserveCursorEvent() {
        self.stopObserveCursorEvent()
        
        self.observerToken = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .cursorUpdate]) { event in
            self.updateCursorPosition()
            self.updateCursorHash()
        }
    }
    
    private func stopObserveCursorEvent() {
        guard let observerToken else {
            return
        }
        
        NSEvent.removeMonitor(observerToken)
    }
    
    func updateCursorPosition() {
        let position = NSEvent.mouseLocation as CGPoint
        
        if position != cursorPosition {
            self.cursorPosition = position
        }
    }
    
    func updateCursorHash() {
        guard let cursorHash = CoreGraphicsPrivate.CGSCurrentCursorSeed?() else {
            return
        }
        
        if cursorHash != self.cursorHash {
            self.cursorHash  = cursorHash
            self.cursorImage = NSCursor.currentSystem?.image
            self.cursorHotspot = NSCursor.currentSystem?.hotSpot
        }
    }
}
