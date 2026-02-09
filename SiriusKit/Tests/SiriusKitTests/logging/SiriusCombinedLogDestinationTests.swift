//
//  SiriusCombinedLogDestinationTests.swift
//  SiriusKitTests
//

import Foundation
import Testing

@testable import SiriusKit

@Suite("SiriusCombinedLogDestination")
struct SiriusCombinedLogDestinationTests {

    @Test("forwards write to all child destinations")
    func forwardsToAll() {
        let dest1 = MockLogDestination()
        let dest2 = MockLogDestination()
        let dest3 = MockLogDestination()

        let combined = SiriusCombinedLogDestination(destinations: [dest1, dest2, dest3])
        combined.write(level: .info, subsystem: "sub", category: "cat", message: "hello",
                       file: "f", function: "fn", line: 1)

        #expect(dest1.entries.count == 1)
        #expect(dest2.entries.count == 1)
        #expect(dest3.entries.count == 1)
        #expect(dest1.entries.first?.message == "hello")
    }

    @Test("works with no destinations")
    func worksWithNoDestinations() {
        let combined = SiriusCombinedLogDestination()
        // Should not crash
        combined.write(level: .info, subsystem: "sub", category: "cat", message: "noop",
                       file: "f", function: "fn", line: 1)
    }

    @Test("addDestination appends and subsequent writes include it")
    func addDestinationWorks() {
        let dest1 = MockLogDestination()
        let dest2 = MockLogDestination()

        let combined = SiriusCombinedLogDestination(destinations: [dest1])
        combined.write(level: .info, subsystem: "sub", category: "cat", message: "first",
                       file: "f", function: "fn", line: 1)

        #expect(dest1.entries.count == 1)
        #expect(dest2.entries.isEmpty)

        combined.addDestination(dest2)
        combined.write(level: .info, subsystem: "sub", category: "cat", message: "second",
                       file: "f", function: "fn", line: 1)

        #expect(dest1.entries.count == 2)
        #expect(dest2.entries.count == 1)
        #expect(dest2.entries.first?.message == "second")
    }

    @Test("nesting combined destinations")
    func nestingCombinedDestinations() {
        let innerDest = MockLogDestination()
        let innerCombined = SiriusCombinedLogDestination(destinations: [innerDest])

        let outerDest = MockLogDestination()
        let outerCombined = SiriusCombinedLogDestination(destinations: [outerDest, innerCombined])

        outerCombined.write(level: .error, subsystem: "sub", category: "cat", message: "nested",
                            file: "f", function: "fn", line: 1)

        #expect(outerDest.entries.count == 1)
        #expect(innerDest.entries.count == 1)
        #expect(innerDest.entries.first?.message == "nested")
        #expect(innerDest.entries.first?.level == .error)
    }

    @Test("conforms to SiriusLogDestination protocol")
    func conformsToProtocol() {
        let combined = SiriusCombinedLogDestination()
        let destination: any SiriusLogDestination = combined
        // Just verify it compiles and is assignable
        #expect(destination is SiriusCombinedLogDestination)
    }
}
