//
//  MockLogDestination.swift
//  SiriusKitTests
//

@testable import SiriusKit

final class MockLogDestination: SiriusLogDestination {
    struct Entry {
        let level: SiriusLogLevel
        let subsystem: String
        let category: String
        let message: String
        let file: String
        let function: String
        let line: UInt
    }

    private(set) var entries: [Entry] = []

    func write(
        level: SiriusLogLevel,
        subsystem: String,
        category: String,
        message: String,
        file: String,
        function: String,
        line: UInt
    ) {
        entries.append(Entry(
            level: level,
            subsystem: subsystem,
            category: category,
            message: message,
            file: file,
            function: function,
            line: line
        ))
    }
}
