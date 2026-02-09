//
//  AddressBarDegradationIndicatorState.swift
//  NoctilucaClient
//

import Foundation

struct AddressBarDegradationIndicatorState: Equatable {
    struct Reasons: OptionSet, Equatable, Sendable {
        let rawValue: UInt32

        static let poorNetworkThroughput         = Reasons(rawValue: 0x1)
        static let poorClientDecodingPerformance = Reasons(rawValue: 0x2)
        static let poorServerEncodingPerformance = Reasons(rawValue: 0x4)
    }

    struct Types: OptionSet, Equatable, Sendable {
        let rawValue: UInt32

        static let resolution         = Types(rawValue: 0x1)
        static let framerate          = Types(rawValue: 0x2)
        static let bitrate            = Types(rawValue: 0x4)
        static let encodingEfficiency = Types(rawValue: 0x8)
    }

    struct AdditionalInfo: OptionSet, Equatable, Sendable {
        let rawValue: UInt32

        static let hardwareEncoderUnavailable = AdditionalInfo(rawValue: 0x1)
    }

    let reasons: Reasons
    let types: Types
    let additionalInfo: AdditionalInfo

    var isDegraded: Bool {
        !reasons.isEmpty || !types.isEmpty || !additionalInfo.isEmpty
    }
}
