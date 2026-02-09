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
