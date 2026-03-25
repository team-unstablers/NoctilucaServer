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
#if DEBUG
            let sourceLocation = "[\(file):\(line)][\(function)] "
#else
            let sourceLocation = ""
#endif
            fputs(
                "[\(SiriusLogTimestamp.now())][\(subsystem)][\(category):\(level.label)]\(sourceLocation)\(message)\n",
                stderr
            )
        } else {
            fputs("\(message)\n", stderr)
        }
    }
}
