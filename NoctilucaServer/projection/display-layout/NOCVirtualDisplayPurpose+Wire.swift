//
//  NOCVirtualDisplayPurpose+Wire.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 4/20/26.
//

import Foundation

extension NOCVirtualDisplayPurpose {
    static let wireVirtualDisplay = "virtual-display"
    static let wireAppStream = "app-stream"

    static func fromWire(_ raw: String?) -> NOCVirtualDisplayPurpose {
        guard let raw, !raw.isEmpty else {
            return .virtualDisplay
        }

        switch raw {
        case Self.wireVirtualDisplay:
            return .virtualDisplay
        case Self.wireAppStream:
            return .appStream
        default:
            return .other(raw)
        }
    }

    var wireString: String {
        switch self {
        case .virtualDisplay:
            return Self.wireVirtualDisplay
        case .appStream:
            return Self.wireAppStream
        case .other(let raw):
            return raw
        }
    }
}
