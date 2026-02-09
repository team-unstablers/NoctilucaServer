//
//  SiriusLogLevel.swift
//  SiriusKit
//

import Foundation
#if canImport(OSLog)
import OSLog
#endif

/// Log levels ordered by severity.
public enum SiriusLogLevel: Int, Comparable, CaseIterable {
    case trace = 0
    case debug
    case info
    case warning
    case error
    case fatal
    case off

    public static func < (lhs: SiriusLogLevel, rhs: SiriusLogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .trace:
            return "TRACE"
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .warning:
            return "WARNING"
        case .error:
            return "ERROR"
        case .fatal:
            return "FATAL"
        case .off:
            return "OFF"
        }
    }

#if canImport(OSLog)
    @available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
    var osLogType: OSLogType {
        switch self {
        case .trace:
            return .debug
        case .debug:
            return .debug
        case .info:
            return .info
        case .warning:
            return .default
        case .error:
            return .error
        case .fatal:
            return .fault
        case .off:
            return .default
        }
    }
#endif
}
