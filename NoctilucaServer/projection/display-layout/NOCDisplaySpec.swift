//
//  NOCDisplaySpec.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 4/17/26.
//

import Foundation
import CoreGraphics

struct NOCDisplaySpecMetadataKey: RawRepresentable, Sendable, Equatable, Hashable {
    let rawValue: String
    
    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension NOCDisplaySpecMetadataKey {
    static let ioKitDisplayModeId = Self(rawValue: "ioKitDisplayModeId")
}

/// Display Spec
struct NOCDisplaySpec: Sendable, Equatable, Hashable {
    /// 뷰포트 사이즈 (포인트 단위)
    let resolution: CGSize
    // 30Hz, 60Hz, 59.94Hz, ...
    let refreshRate: Double
    let scaleFactor: CGFloat
    
    let metadata: [NOCDisplaySpecMetadataKey: String]
}

extension NOCDisplaySpec {
    // TODO: Color depth나 pixel format 등도 비교해야 함!!
    func compatible(with anotherSpec: NOCDisplaySpec) -> Bool {
        if let ioKitDisplayModeId = metadata[.ioKitDisplayModeId],
           anotherSpec.metadata[.ioKitDisplayModeId] == ioKitDisplayModeId {
            return true
        }
        
        return (
            resolution  == anotherSpec.resolution  &&
            refreshRate == anotherSpec.refreshRate &&
            scaleFactor == anotherSpec.scaleFactor
        )
    }
}


extension NOCDisplaySpec {
    static func from(cgDisplayMode cgMode: CGDisplayMode) -> NOCDisplaySpec {
        let scaleFactor = Double(cgMode.pixelHeight) / Double(cgMode.height)

        return NOCDisplaySpec(
            resolution: CGSize(width: cgMode.width, height: cgMode.height),
            refreshRate: cgMode.refreshRate,
            scaleFactor: scaleFactor,
            metadata: [
                .ioKitDisplayModeId: String(cgMode.ioDisplayModeID)
            ]
        )
    }
}

extension NOCDisplaySpec: CustomStringConvertible {
    var description: String {
        let width = Int(resolution.width)
        let height = Int(resolution.height)
        let refresh = refreshRate > 0
            ? String(format: "%g", refreshRate)
            : "?"
        return "\(width)x\(height)@\(refresh)Hz @\(scaleFactor)x"
    }
}
