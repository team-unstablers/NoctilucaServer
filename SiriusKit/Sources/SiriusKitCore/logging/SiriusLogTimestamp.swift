//
//  SiriusLogTimestamp.swift
//  SiriusKit
//

import Foundation

enum SiriusLogTimestamp {
    static func now() -> String {
        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
            return Date().ISO8601Format(.init(includingFractionalSeconds: true, timeZone: .current))
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}
