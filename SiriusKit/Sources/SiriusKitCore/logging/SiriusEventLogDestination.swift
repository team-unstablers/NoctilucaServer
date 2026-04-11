//
//  SiriusLogDestination.swift
//  SiriusKit
//

/// Destination abstraction for logs.
public protocol SiriusEventLogDestination: Sendable {
    func write(
        message: String,
    )
}
