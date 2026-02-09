//
//  SiriusLoggerTests.swift
//  SiriusKitTests
//

import Foundation
import Testing

@testable import SiriusKit

@Suite("SiriusLogger")
struct SiriusLoggerTests {

    @Test("log dispatches to all destinations")
    func logDispatchesToAllDestinations() {
        let dest1 = MockLogDestination()
        let dest2 = MockLogDestination()
        let logger = SiriusLogger(category: "Test", destinations: [dest1, dest2])

        // Ensure minimum level allows info
        SiriusLogger.configure(minimumLevel: .info)

        logger.info("hello")

        #expect(dest1.entries.count == 1)
        #expect(dest2.entries.count == 1)
        #expect(dest1.entries.first?.message == "hello")
        #expect(dest1.entries.first?.category == "Test")
    }

    @Test("log returns false when level is .off")
    func logReturnsFalseForOff() {
        let dest = MockLogDestination()
        let logger = SiriusLogger(category: "Test", destinations: [dest])

        let result = logger.log(.off, message: "should not appear")

        #expect(result == false)
        #expect(dest.entries.isEmpty)
    }

    @Test("log returns false when below minimum level")
    func logReturnsFalseBelowMinimum() {
        SiriusLogger.configure(minimumLevel: .warning)

        let dest = MockLogDestination()
        let logger = SiriusLogger(category: "Test", destinations: [dest])

        let result = logger.info("below minimum")

        #expect(result == false)
        #expect(dest.entries.isEmpty)

        // Restore default
        SiriusLogger.configure(minimumLevel: .info)
    }

    @Test("minimum level filtering passes correct levels")
    func minimumLevelFiltering() {
        SiriusLogger.configure(minimumLevel: .warning)

        let dest = MockLogDestination()
        let logger = SiriusLogger(category: "Test", destinations: [dest])

        logger.info("filtered out")
        logger.warning("passes")
        logger.error("also passes")

        #expect(dest.entries.count == 2)
        #expect(dest.entries[0].level == .warning)
        #expect(dest.entries[1].level == .error)

        // Restore default
        SiriusLogger.configure(minimumLevel: .info)
    }

    @Test("verbosity preset maps to correct minimum level")
    func verbosityMapping() {
        SiriusLogger.setVerbosity(.verbose)
        #expect(SiriusLogger.currentMinimumLevel() == .trace)

        SiriusLogger.setVerbosity(.normal)
        #expect(SiriusLogger.currentMinimumLevel() == .info)

        SiriusLogger.setVerbosity(.quiet)
        #expect(SiriusLogger.currentMinimumLevel() == .off)

        // Restore default
        SiriusLogger.configure(minimumLevel: .info)
    }
}
