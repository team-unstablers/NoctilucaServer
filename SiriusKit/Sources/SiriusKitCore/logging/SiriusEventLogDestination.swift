//
//  SiriusLogDestination.swift
//  SiriusKit
//

/// Destination abstraction for logs.
public protocol SiriusEventLogDestination {
    func write(
        message: String,
    )
}
