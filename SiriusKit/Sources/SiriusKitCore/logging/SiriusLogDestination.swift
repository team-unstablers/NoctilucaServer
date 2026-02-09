//
//  SiriusLogDestination.swift
//  SiriusKit
//

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
