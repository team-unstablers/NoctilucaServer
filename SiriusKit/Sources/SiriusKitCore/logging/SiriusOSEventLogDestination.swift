//
//  SiriusOSLogDestination.swift
//  SiriusKit
//

#if canImport(OSLog)
import OSLog

@available(macOS 11.0, iOS 14.0, tvOS 14.0, watchOS 7.0, *)
public struct SiriusOSEventLogDestination: SiriusEventLogDestination {
    private let logger: Logger

    public init() {
        self.logger = Logger(subsystem: "so.libsirius.SiriusKit.EventLog", category: "EventLog")
    }

    public func write(
        message: String,
    ) {
        logger.log(
            level: .default,
            "\(message)"
        )
    }
}
#endif
