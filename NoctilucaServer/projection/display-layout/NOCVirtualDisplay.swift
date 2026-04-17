//
//  NOCVirtualDisplay.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 4/17/26.
//

import Foundation
import CoreGraphics

// eg) "app.noctiluca.server.0F3B1E5A-….virtual-display.A12C-…"
typealias NOCVirtualDisplayIdentifier = String

enum NOCVirtualDisplayPurpose: Sendable, Equatable, Hashable {
    /// 가상 디스플레이 용도
    case virtualDisplay
    /// AppStream 전용
    case appStream
    /// 기타 용도 (아직 지원하지 않음)
    case other(String)
}

struct NOCVirtualDisplayMetadataKey: RawRepresentable, Sendable, Equatable, Hashable {
    let rawValue: String
    
    init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension NOCVirtualDisplayMetadataKey {
    
}

final class NOCVirtualDisplayHandle: Sendable {
    let identifier: NOCVirtualDisplayIdentifier
    let displayID: CGDirectDisplayID
    let purpose: NOCVirtualDisplayPurpose
    let metadata: [NOCVirtualDisplayMetadataKey: String]
    
    init(identifier: NOCVirtualDisplayIdentifier,
         displayID: CGDirectDisplayID,
         purpose: NOCVirtualDisplayPurpose,
         metadata: [NOCVirtualDisplayMetadataKey : String])
    {
        self.identifier = identifier
        self.displayID = displayID
        self.purpose = purpose
        self.metadata = metadata
    }
}
