//
//  SiriusCombinedLogDestination.swift
//  SiriusKit
//

import Foundation

/// A composite log destination that forwards writes to multiple child destinations.
public final class SiriusCombinedLogDestination: SiriusLogDestination {
    private let queue = DispatchQueue(label: "org.noctiluca.sirius.logger.combined")
    private var destinations: [any SiriusLogDestination] = []

    public init() {}

    public init(destinations: [any SiriusLogDestination]) {
        self.destinations = destinations
    }

    /// Adds a child destination. Thread-safe.
    public func addDestination(_ destination: any SiriusLogDestination) {
        queue.sync {
            destinations.append(destination)
        }
    }

    // MARK: - SiriusLogDestination

    public func write(
        level: SiriusLogLevel,
        subsystem: String,
        category: String,
        message: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let snapshot: [any SiriusLogDestination] = queue.sync { destinations }
        for destination in snapshot {
            destination.write(
                level: level,
                subsystem: subsystem,
                category: category,
                message: message,
                file: file,
                function: function,
                line: line
            )
        }
    }
}
