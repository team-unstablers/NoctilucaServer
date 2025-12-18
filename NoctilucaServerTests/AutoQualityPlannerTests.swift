//
//  AutoQualityPlannerTests.swift
//  NoctilucaServerTests
//
//  Created by Coding Assistant on 12/18/25.
//

import XCTest
import CoreGraphics
import SiriusKit
@testable import NoctilucaServer

final class AutoQualityPlannerTests: XCTestCase {
    
    func testInitialBitrateUsesPreset() {
        let resolution = CGSize(width: 1920, height: 1080)
        let fps: Float = 60
        let preset = AutoQualityPreset.preset(for: .avc1, resolution: resolution, frameRate: fps)
        
        let planner = AutoQualityPlanner(codec: .avc1, resolution: resolution, frameRate: fps, strategy: .balanced)
        
        XCTAssertEqual(planner.targetBitrateKbps(), preset.targetBitrateKbps)
        XCTAssertEqual(planner.maxBitrateKbps(), preset.maxBitrateKbps)
        XCTAssertTrue(planner.plannedDegradations().isEmpty)
    }
    
    func testCriticalDegradationLowersBitrateAndAddsSteps() {
        let planner = makePlanner()
        let baselineTarget = planner.targetBitrateKbps()
        
        // Drop ratio 20% -> critical degradation; needs multiple ticks to pass score threshold
        planner.feed(report: makeReport(received: 100, decoded: 80, dropped: 20, decodeMs: 5))
        planner.feed(report: makeReport(received: 100, decoded: 80, dropped: 20, decodeMs: 5))
        
        XCTAssertLessThan(planner.targetBitrateKbps(), baselineTarget)
        XCTAssertEqual(planner.plannedDegradations().count, 2, "Critical degradation should advance two steps")
    }
    
    func testRecoveryRollsBackDegradationsAndRaisesBitrate() {
        let planner = makePlanner()
        planner.feed(report: makeReport(received: 100, decoded: 80, dropped: 20, decodeMs: 5))
        planner.feed(report: makeReport(received: 100, decoded: 80, dropped: 20, decodeMs: 5)) // degrade to 2 steps
        let degradedTarget = planner.targetBitrateKbps()
        XCTAssertEqual(planner.plannedDegradations().count, 2)
        
        // 1st stable batch: consume cooldown and accumulate recovery score
        for _ in 0..<6 {
            planner.feed(report: makeReport(received: 100, decoded: 100, dropped: 0, decodeMs: 3))
        }
        let midTarget = planner.targetBitrateKbps()
        XCTAssertEqual(planner.plannedDegradations().count, 1)
        XCTAssertGreaterThan(midTarget, degradedTarget)
        
        // 2nd stable batch -> remove remaining step
        for _ in 0..<6 {
            planner.feed(report: makeReport(received: 100, decoded: 100, dropped: 0, decodeMs: 3))
        }
        XCTAssertTrue(planner.plannedDegradations().isEmpty)
        XCTAssertGreaterThan(planner.targetBitrateKbps(), midTarget)
    }
    
    func testBackpressureStreakTriggersCriticalCut() {
        let planner = makePlanner()
        let baselineTarget = planner.targetBitrateKbps()
        
        planner.feed(backpressure: true)  // mild
        let afterFirst = planner.targetBitrateKbps() // no degrade yet
        planner.feed(backpressure: true)  // reaches threshold -> critical
        let afterSecond = planner.targetBitrateKbps()
        
        XCTAssertEqual(afterFirst, baselineTarget)
        XCTAssertLessThan(afterSecond, afterFirst)
        XCTAssertGreaterThanOrEqual(planner.plannedDegradations().count, 2)
    }
}

private extension AutoQualityPlannerTests {
    func makePlanner(strategy: AutoQualityStrategy = .balanced) -> AutoQualityPlanner {
        AutoQualityPlanner(
            codec: .avc1,
            resolution: CGSize(width: 1920, height: 1080),
            frameRate: 60,
            strategy: strategy
        )
    }
    
    func makeReport(received: UInt32, decoded: UInt32, dropped: UInt32, decodeMs: UInt32) -> ProjectionPerformanceReport {
        ProjectionPerformanceReport(
            identifier: UUID(),
            receivedFrameCount: received,
            decodedFrameCount: decoded,
            droppedFrameCount: dropped,
            averageDecodeTimeMs: decodeMs
        )
    }
}
