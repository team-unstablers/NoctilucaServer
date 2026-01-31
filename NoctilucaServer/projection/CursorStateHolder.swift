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
    
    init() {
        do {
            try CoreGraphicsPrivate.open()
        } catch {
            logger.error("failed to load CoreGraphics library")
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
