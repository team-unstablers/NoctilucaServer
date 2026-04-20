//
//  DisplayLayoutManager.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/31/26.
//

import Foundation
import Observation

import SiriusKitClient

@MainActor
@Observable
final class DisplayLayoutManager {
    typealias DisplayID = Int

    @ObservationIgnored
    let logger = NoctilucaLogger(category: "DisplayLayoutManager")

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
        displayLayouts[displayID] = mergeDisplayInfo(displayInfo, preservingThumbnailFrom: displayLayouts[displayID])
    }

    func consumeDisplayChangeEvent(_ event: DisplayChangedEvent) {
        let displayID = DisplayID(event.display.displayID)

        switch event.eventType {
        case .connected, .modified, .becamePrimary:
            displayLayouts[displayID] = mergeDisplayInfo(event.display, preservingThumbnailFrom: displayLayouts[displayID])
        case .disconnected:
            displayLayouts.removeValue(forKey: displayID)
        default:
            break
        }
    }

    /// 새 DisplayInfo에 thumbnail이 없으면 기존 thumbnail을 보존합니다.
    private func mergeDisplayInfo(_ new: DisplayInfo, preservingThumbnailFrom existing: DisplayInfo?) -> DisplayInfo {
        let thumbnail = new.thumbnail ?? existing?.thumbnail
        guard thumbnail != nil else { return new }

        return DisplayInfo(
            displayID: new.displayID,
            kind: new.kind,
            displayName: new.displayName,
            state: new.state,
            bounds: new.bounds,
            refreshRate: new.refreshRate,
            colorDepth: new.colorDepth,
            dynamicRange: new.dynamicRange,
            colorProfile: new.colorProfile,
            physicalSizeInfo: new.physicalSizeInfo,
            scaleFactor: new.scaleFactor,
            rotation: new.rotation,
            supportedSpecs: new.supportedSpecs,
            thumbnail: thumbnail,
            metadata: new.metadata,
            flags: new.flags,
            virtualDisplayIdentifier: new.virtualDisplayIdentifier,
        )
    }
    
}
