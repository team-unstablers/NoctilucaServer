//
//  SiriusLogger.swift
//  SiriusKit
//
//  Reimplemented logger inspired by legacy NOCLogger with better configurability
//  and platform-aware destinations.
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

/// Backward-compatible verbosity presets.
public enum SiriusLogVerbosity {
    case verbose
    case normal
    case quiet

    var minimumLevel: SiriusLogLevel {
        switch self {
        case .verbose:
            // FIXME: vverbose같은거 만들까?
            return .trace
        case .normal:
            return .info
        case .quiet:
            return .off
        }
    }
}

/// Destination abstraction for logs.
public protocol SiriusLogDestination {
    func write(
        level: SiriusLogLevel,
        subsystem: String,
        category: String,
        message: String,
        file: String,
        function: String,
        line: UInt
    )
}

public struct SiriusConsoleLogDestination: SiriusLogDestination {
    private let includeMetadata: Bool

    public init(includeMetadata: Bool = true) {
        self.includeMetadata = includeMetadata
    }

    public func write(
        level: SiriusLogLevel,
        subsystem: String,
        category: String,
        message: String,
        file: String,
        function: String,
        line: UInt
    ) {
        guard level != .off else { return }

        if includeMetadata {
            fputs(
                "[\(timestamp())][\(subsystem)][\(category):\(level.label)][\(file):\(line)][\(function)] \(message)\n",
                stderr
            )
        } else {
            fputs("\(message)\n", stderr)
        }
    }

    private func timestamp() -> String {
        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
            return Date().ISO8601Format(.init(includingFractionalSeconds: true, timeZone: .current))
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        formatter.timeZone = .current
        return formatter.string(from: Date())
    }
}

#if canImport(OSLog)
@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public struct SiriusOSLogDestination: SiriusLogDestination {
    private let logger: Logger

    public init(subsystem: String, category: String) {
        self.logger = Logger(subsystem: subsystem, category: category)
    }

    public func write(
        level: SiriusLogLevel,
        subsystem: String,
        category: String,
        message: String,
        file: String,
        function: String,
        line: UInt
    ) {
        guard level != .off else { return }
        logger.log(
            level: level.osLogType,
            "[\(level.label)] \(message, privacy: .public)"
        )
    }
}
#endif

public final class SiriusLogger {
    public typealias DestinationBuilder = @Sendable (_ subsystem: String, _ category: String) -> [any SiriusLogDestination]

    public static var defaultSubsystem: String {
        Bundle.main.bundleIdentifier ?? "SiriusKit"
    }

    private static let configurationQueue = DispatchQueue(label: "org.noctiluca.sirius.logger.config")
    private static var minimumLevel: SiriusLogLevel = .info
    private static var destinationBuilder: DestinationBuilder = SiriusLogger.defaultDestinations

    private let subsystem: String
    private let category: String
    private let destinations: [any SiriusLogDestination]

    public init(
        category: String,
        subsystem: String = SiriusLogger.defaultSubsystem,
        destinations: [any SiriusLogDestination]? = nil
    ) {
        self.subsystem = subsystem
        self.category = category
        self.destinations = destinations ?? SiriusLogger.makeDestinations(subsystem: subsystem, category: category)
    }

    public static func configure(
        minimumLevel: SiriusLogLevel? = nil,
        destinationBuilder: DestinationBuilder? = nil
    ) {
        configurationQueue.sync {
            if let minimumLevel {
                Self.minimumLevel = minimumLevel
            }

            if let destinationBuilder {
                Self.destinationBuilder = destinationBuilder
            }
        }
    }

    public static func setVerbosity(_ verbosity: SiriusLogVerbosity) {
        configure(minimumLevel: verbosity.minimumLevel)
    }

    public static func currentMinimumLevel() -> SiriusLogLevel {
        configurationQueue.sync { minimumLevel }
    }

    @discardableResult
    public func log(
        _ level: SiriusLogLevel,
        message: @autoclosure @escaping () -> String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) -> Bool {
        guard level != .off else { return false }
        guard level >= SiriusLogger.currentMinimumLevel(), !destinations.isEmpty else { return false }

        let resolvedMessage = message()
        destinations.forEach {
            $0.write(
                level: level,
                subsystem: subsystem,
                category: category,
                message: resolvedMessage,
                file: file,
                function: function,
                line: line
            )
        }

        return true
    }
    
    @inlinable
    @discardableResult
    public func trace(
        _ message: @autoclosure @escaping () -> String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) -> Bool {
#if DEBUG
        // 릴리즈 빌드에서는 trace 로그를 컴파일하지 않도록 한다
        log(.trace, message: message(), file: file, function: function, line: line)
#endif
        
        return false
    }


    @inlinable
    @discardableResult
    public func debug(
        _ message: @autoclosure @escaping () -> String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) -> Bool {
#if DEBUG
        // 릴리즈 빌드에서는 debug 로그를 컴파일하지 않도록 한다
        log(.debug, message: message(), file: file, function: function, line: line)
#endif
        return false
    }

    @inlinable
    @discardableResult
    public func info(
        _ message: @autoclosure @escaping () -> String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) -> Bool {
        log(.info, message: message(), file: file, function: function, line: line)
    }

    @inlinable
    @discardableResult
    public func warning(
        _ message: @autoclosure @escaping () -> String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) -> Bool {
        log(.warning, message: message(), file: file, function: function, line: line)
    }

    @inlinable
    @discardableResult
    public func error(
        _ message: @autoclosure @escaping () -> String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) -> Bool {
        log(.error, message: message(), file: file, function: function, line: line)
    }

    @inlinable
    @discardableResult
    public func fatal(
        _ message: @autoclosure @escaping () -> String,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) -> Bool {
        log(.fatal, message: message(), file: file, function: function, line: line)
    }

    private static func makeDestinations(subsystem: String, category: String) -> [any SiriusLogDestination] {
        configurationQueue.sync { destinationBuilder(subsystem, category) }
    }

    private static func defaultDestinations(subsystem: String, category: String) -> [any SiriusLogDestination] {
#if canImport(OSLog)
        if #available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *) {
            return [SiriusOSLogDestination(subsystem: subsystem, category: category)]
        } else {
            return [SiriusConsoleLogDestination()]
        }
#else
        return [SiriusConsoleLogDestination()]
#endif
    }
}
