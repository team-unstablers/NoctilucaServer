//
//  CodecQuality+Helpers.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 3/8/26.
//

import Foundation
import SiriusKit

extension Codec.Quality {
    var modeTag: String {
        switch self {
        case .auto: return "auto"
        case .constantBitrate: return "constantBitrate"
        case .fixedQuality: return "fixedQuality"
        case .lossless: return "lossless"
        case .variableBitrate: return "variableBitrate"
        }
    }

    static func defaultValue(for tag: String) -> Codec.Quality {
        switch tag {
        case "auto": return .auto(mode: .balancedPriority)
        case "constantBitrate": return .constantBitrate(bitrateKbps: 3000)
        case "lossless": return .lossless(mode: .balancedPriority)
        case "variableBitrate": return .variableBitrate(targetBitrateKbps: 3000, maxBitrateKbps: 6000)
        default: return .auto(mode: .balancedPriority)
        }
    }
}
