//
//  NOCDisplaySpec+VirtualDisplay.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 4/17/26.
//

extension NOCDisplaySpec {
    func asCGVirtualDisplayModes() -> [CGVirtualDisplayMode] {
        guard let primaryMode = CGVirtualDisplayMode(
            width: UInt32(self.resolution.width),
            height: UInt32(self.resolution.height),
            refreshRate: self.refreshRate
        ) else {
            return []
        }
        
        if self.scaleFactor > 1,
           let nativeMode = CGVirtualDisplayMode(
                width: UInt32(self.resolution.width * self.scaleFactor),
                height: UInt32(self.resolution.height * self.scaleFactor),
                refreshRate: self.refreshRate
           )
        {
            return [nativeMode, primaryMode]
        } else {
            return [primaryMode]
        }
    }
}
