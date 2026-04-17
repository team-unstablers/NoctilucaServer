//
//  DisplayLayoutManager+DisplaySpec.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 4/17/26.
//

import Foundation
import CoreGraphics

import SiriusKitCore

@MainActor
fileprivate func cgEval(_ action: () -> CGError?) throws {
    let error = action()
    guard error == .success else {
        throw DisplayLayoutManagerError.displaySpecApplyFailure(error)
    }
}

extension DisplayLayoutManager {
    func supportedSpecs(for displayID: CGDirectDisplayID) -> [NOCDisplaySpec] {
        guard let cfModes = CGDisplayCopyAllDisplayModes(displayID, [
            kCGDisplayShowDuplicateLowResolutionModes: true
        ] as CFDictionary) else {
            return []
        }
        
        guard let cgModes = cfModes as? [CGDisplayMode] else {
            return []
        }
        
        let specs = cgModes.map {
            NOCDisplaySpec.from(cgDisplayMode: $0)
        }
        
        return specs
    }
    
    /// 주어진 스펙이 적용 가능한지 확인합니다.
    func preflightSpec(to displayID: CGDirectDisplayID, spec: NOCDisplaySpec) -> Bool {
        let specs = supportedSpecs(for: displayID)
        
        guard !specs.isEmpty else {
            return false
        }
        
        return specs.contains { $0.compatible(with: spec) }
    }
    
    func applySpec(to displayID: CGDirectDisplayID, spec: NOCDisplaySpec) throws {
        guard let cfModes = CGDisplayCopyAllDisplayModes(
                displayID,
                [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
              ),
              let cgModes = cfModes as? [CGDisplayMode]
        else {
            throw DisplayLayoutManagerError.displaySpecNotCompatible
        }
        
        
        let compatibleSpecs = cgModes.filter { NOCDisplaySpec.from(cgDisplayMode: $0).compatible(with: spec) }
        
        guard let mostCompatibleSpec = compatibleSpecs.first else {
            throw DisplayLayoutManagerError.displaySpecNotCompatible
        }
        let error = CGDisplaySetDisplayMode(displayID, mostCompatibleSpec, nil)
        
        guard error == .success else {
            logger.error("failed to apply spec \(spec) to display #\(displayID): CGError \(error)")
            throw DisplayLayoutManagerError.displaySpecApplyFailure(error)
        }
    }
    
    // 주어진 ID의 디스플레이를 메인 디스플레이로 승격시킵니다.
    func promoteDisplay(toMain displayID: CGDirectDisplayID) throws {
        if CGMainDisplayID() == displayID {
            return
        }
        
        let layout = displayLayouts.snapshot().mapValues {
            $0.frame
        }
        
        try applyLayout(layout: layout, mainDisplayID: displayID)
    }
    
    /// 주어진 레이아웃을 적용합니다.
    ///
    /// NOCScreen 좌표계는 전체 viewport 좌상단이 (0,0)이고 Y축이 아래로 증가하는 X11-like 좌표계입니다.
    /// `CGConfigureDisplayOrigin`은 메인 디스플레이 좌상단을 (0,0)으로 삼는 global display coordinate를
    /// 쓰며, Y축 방향은 동일합니다. 따라서 `mainDisplayID`의 origin만큼 평행 이동만 해주면 되고,
    /// 결과적으로 해당 디스플레이가 (0,0)에 위치하게 되어 자동으로 메인으로 지정됩니다.
    func applyLayout(layout: [CGDirectDisplayID: CGRect], mainDisplayID: CGDirectDisplayID? = nil) throws {
        let mainDisplayID = mainDisplayID ?? CGMainDisplayID()

        guard let mainFrame = layout[mainDisplayID] else {
            logger.error("applyLayout: main display #\(mainDisplayID) is not in the given layout")
            throw DisplayLayoutManagerError.unknownError
        }

        var configRef: CGDisplayConfigRef? = nil
        try cgEval { CGBeginDisplayConfiguration(&configRef) }

        var committed = false
        defer {
            if !committed, let configRef {
                CGCancelDisplayConfiguration(configRef)
            }
        }

        for (displayID, frame) in layout {
            let cgX = Int32(frame.origin.x - mainFrame.origin.x)
            let cgY = Int32(frame.origin.y - mainFrame.origin.y)

            try cgEval { CGConfigureDisplayOrigin(configRef, displayID, cgX, cgY) }
        }

        try cgEval { CGCompleteDisplayConfiguration(configRef, [.forSession]) }
        committed = true
    }
}
