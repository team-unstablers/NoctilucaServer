//
//  SiriusConsoleLogDestination.swift
//  SiriusKit
//

import Foundation

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
                "[\(SiriusLogTimestamp.now())][\(subsystem)][\(category):\(level.label)][\(file):\(line)][\(function)] \(message)\n",
                stderr
            )
        } else {
            fputs("\(message)\n", stderr)
        }
    }
}
