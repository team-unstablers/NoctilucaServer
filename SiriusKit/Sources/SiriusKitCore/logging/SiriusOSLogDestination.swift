//
//  SiriusOSLogDestination.swift
//  SiriusKit
//

#if canImport(OSLog)
import OSLog

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
