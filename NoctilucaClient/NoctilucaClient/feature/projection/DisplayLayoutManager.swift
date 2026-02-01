//
//  DisplayLayoutManager.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/31/26.
//

import Foundation
import Combine

import SiriusKitClient

@MainActor
class DisplayLayoutManager: ObservableObject {
    typealias DisplayID = Int
    
    let logger = NoctilucaLogger(category: "DisplayLayoutManager")
    
    @Published
    private(set) var displayLayouts: [DisplayID: DisplayInfo] = [:]
    
    var primaryDisplayID: DisplayID? {
        displayLayouts.first { $0.value.state.isPrimary }?.key
    }
    
    nonisolated init() {
        
    }
    
    func reset() {
        displayLayouts.removeAll()
    }
    
    func update(_ displayInfo: DisplayInfo) {
        let displayID = DisplayID(displayInfo.displayID)
        
        displayLayouts[displayID] = displayInfo
    }
    
    func consumeDisplayChangeEvent(_ event: DisplayChangedEvent) {
        let displayID = DisplayID(event.display.displayID)
        
        switch event.eventType {
        case .connected, .modified, .becamePrimary:
            displayLayouts[displayID] = event.display
        case .disconnected:
            displayLayouts.removeValue(forKey: displayID)
        default:
            break
        }
    }
    
}
