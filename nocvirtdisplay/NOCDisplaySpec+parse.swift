//
//  NOCDisplaySpec+parse.swift
//  nocvirtdisplay
//
//  Created by Gyuhwan Park on 4/17/26.
//

import Foundation
import CoreGraphics

extension NOCDisplaySpec {
    enum ParseError: Error, CustomStringConvertible {
        case empty
        case invalidResolution(String)
        case invalidRefreshRate(String)
        case invalidScaleFactor(String)

        var description: String {
            switch self {
            case .empty:
                return "mode string is empty"
            case .invalidResolution(let s):
                return "invalid resolution: '\(s)' (expected WIDTHxHEIGHT)"
            case .invalidRefreshRate(let s):
                return "invalid refresh rate: '\(s)'"
            case .invalidScaleFactor(let s):
                return "invalid scale factor: '\(s)' (expected <number>x)"
            }
        }
    }

    /// Parses single mode string like `640x480@59.94+1x`.
    ///
    /// Format: `WIDTHxHEIGHT@REFRESH[+SCALEx]`
    /// - `+SCALEx` is optional (defaults to `1`).
    /// - `@REFRESH` accepts `?` as unknown (maps to `0`).
    static func parse(_ string: String) throws -> NOCDisplaySpec {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw ParseError.empty
        }

        let scalePieces = trimmed.split(
            separator: "+",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let resolutionAndRefresh = String(scalePieces[0])

        let scaleFactor: CGFloat
        if scalePieces.count == 2 {
            let scalePart = String(scalePieces[1])
            guard scalePart.hasSuffix("x") else {
                throw ParseError.invalidScaleFactor(scalePart)
            }
            let numericPart = String(scalePart.dropLast())
            guard let value = Double(numericPart), value > 0 else {
                throw ParseError.invalidScaleFactor(scalePart)
            }
            scaleFactor = CGFloat(value)
        } else {
            scaleFactor = 1
        }

        let refreshPieces = resolutionAndRefresh.split(
            separator: "@",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let resolutionPart = String(refreshPieces[0])

        let refreshRate: Double
        if refreshPieces.count == 2 {
            let refreshPart = String(refreshPieces[1])
            if refreshPart == "?" {
                refreshRate = 0
            } else if let value = Double(refreshPart), value >= 0 {
                refreshRate = value
            } else {
                throw ParseError.invalidRefreshRate(refreshPart)
            }
        } else {
            refreshRate = 0
        }

        let dims = resolutionPart.split(
            separator: "x",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard dims.count == 2,
              let width = Int(dims[0]),
              let height = Int(dims[1]),
              width > 0, height > 0
        else {
            throw ParseError.invalidResolution(resolutionPart)
        }

        return NOCDisplaySpec(
            resolution: CGSize(width: width, height: height),
            refreshRate: refreshRate,
            scaleFactor: scaleFactor,
            metadata: [:]
        )
    }

    /// Parses comma-separated mode list like `640x480@60+1x,1280x720@60+2x`.
    static func parseList(_ stringList: [String]) throws -> [NOCDisplaySpec] {
        try stringList
            .map { try parse($0) }
    }
}
