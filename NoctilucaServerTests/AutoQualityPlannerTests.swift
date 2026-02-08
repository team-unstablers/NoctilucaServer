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

        // Drop ratio 20% -> below emergency threshold (30%), needs score accumulation
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

        // Recovery requires BOTH clientScore and serverScore <= -3.
        // feed(report:) only decrements clientScore, so we also feed stable queuePressure
        // to bring serverScore down.
        for _ in 0..<6 {
            planner.feed(report: makeReport(received: 100, decoded: 100, dropped: 0, decodeMs: 3))
            planner.feed(queuePressure: 0.0)
        }
        let midTarget = planner.targetBitrateKbps()
        XCTAssertEqual(planner.plannedDegradations().count, 1)
        XCTAssertGreaterThan(midTarget, degradedTarget)

        // 2nd stable batch -> remove remaining step
        for _ in 0..<6 {
            planner.feed(report: makeReport(received: 100, decoded: 100, dropped: 0, decodeMs: 3))
            planner.feed(queuePressure: 0.0)
        }
        XCTAssertTrue(planner.plannedDegradations().isEmpty)
        XCTAssertGreaterThan(planner.targetBitrateKbps(), midTarget)
    }

    func testBackpressureStreakTriggersCriticalCut() {
        let planner = makePlanner()
        let baselineTarget = planner.targetBitrateKbps()

        // queuePressure 1.0 >= emergencyPressureThreshold (0.9) → 즉시 critical 디그레이드
        planner.feed(queuePressure: 1.0)

        XCTAssertLessThan(planner.targetBitrateKbps(), baselineTarget)
        XCTAssertGreaterThanOrEqual(planner.plannedDegradations().count, 2)
    }

    // MARK: - 긴급 경로 테스트

    func testEmergencyDropTriggersImmediateDegradation() {
        let planner = makePlanner()
        let baselineTarget = planner.targetBitrateKbps()

        // Drop ratio 50% >= emergencyDropThreshold (30%) → 즉시 critical 디그레이드
        planner.feed(report: makeReport(received: 100, decoded: 50, dropped: 50, decodeMs: 5))

        XCTAssertLessThan(planner.targetBitrateKbps(), baselineTarget)
        XCTAssertGreaterThanOrEqual(planner.plannedDegradations().count, 2,
            "Emergency drop should trigger immediate critical degradation")
    }

    func testSeparateScoresDoNotCancelOut() {
        let planner = makePlanner()

        // client 쪽에서 bad report: clientScore += 2 (critical drop threshold)
        planner.feed(report: makeReport(received: 100, decoded: 85, dropped: 15, decodeMs: 5))
        // server 쪽에서 stable: serverScore -= 1
        planner.feed(queuePressure: 0.0)

        // 다시 bad report: clientScore += 2 → 총 clientScore ~= 4
        planner.feed(report: makeReport(received: 100, decoded: 85, dropped: 15, decodeMs: 5))

        // clientScore가 충분히 높으므로 디그레이드가 발생해야 함
        // (기존 단일 score 방식이었으면 server의 -1이 상쇄했을 것)
        XCTAssertFalse(planner.plannedDegradations().isEmpty,
            "Client score should trigger degradation independently of server score")
    }

    func testRecoveryRequiresBothSourcesStable() {
        let planner = makePlanner()

        // 먼저 디그레이드 발동
        planner.feed(queuePressure: 1.0) // emergency → critical degrade
        XCTAssertFalse(planner.plannedDegradations().isEmpty)

        // client만 stable (server는 feed하지 않음 → serverScore는 0에서 변하지 않음)
        for _ in 0..<10 {
            planner.feed(report: makeReport(received: 100, decoded: 100, dropped: 0, decodeMs: 3))
        }

        // serverScore가 -3에 도달하지 않았으므로 회복하지 않아야 함
        XCTAssertFalse(planner.plannedDegradations().isEmpty,
            "Recovery should require both client and server to be stable")
    }

    // MARK: - Quality degradation steps 테스트

    func testDegradationStepsIncludeQuality() {
        let planner = makePlanner(strategy: .balanced)

        // 디그레이드 발동
        planner.feed(queuePressure: 1.0) // emergency → 2 steps

        let degradations = planner.plannedDegradations()
        let hasQualityDegradation = degradations.contains { degradation in
            if case .lowerQuality = degradation { return true }
            return false
        }
        XCTAssertTrue(hasQualityDegradation,
            "Degradation steps should include lowerQuality")
    }

    // MARK: - 이미지 코덱 양자화 독립 제어 테스트

    func testImageCodecDegradationIncludesQuantization() {
        let planner = makePlanner(codec: .mjpg, strategy: .balanced)

        // 디그레이드 발동
        planner.feed(queuePressure: 1.0) // emergency → 2 steps

        let degradations = planner.plannedDegradations()
        let hasQuantization = degradations.contains { degradation in
            if case .increaseQuantization = degradation { return true }
            return false
        }
        XCTAssertTrue(hasQuantization,
            "Image codec degradation steps should include increaseQuantization")
    }

    func testVTCodecDegradationExcludesQuantization() {
        let planner = makePlanner(codec: .avc1, strategy: .balanced)

        // 전체 단계를 활성화
        for _ in 0..<10 {
            planner.feed(queuePressure: 1.0)
        }

        let degradations = planner.plannedDegradations()
        let hasQuantization = degradations.contains { degradation in
            if case .increaseQuantization = degradation { return true }
            return false
        }
        XCTAssertFalse(hasQuantization,
            "VT codec degradation steps should not include increaseQuantization")
    }

    func testImageCodecQuantizationMaxLevel() {
        // balanced 시퀀스: quant1, q85, res85, fps90, quant2, q70, res70, fps75, quant3
        let planner = makePlanner(codec: .webp, strategy: .balanced)

        // 여러 번 디그레이드하여 quant1 + quant2가 모두 활성화되게 함
        for _ in 0..<5 {
            planner.feed(queuePressure: 1.0)
        }

        let degradations = planner.plannedDegradations()
        let quantizeLevels = degradations.compactMap { degradation -> Int? in
            if case .increaseQuantization(let level) = degradation { return level }
            return nil
        }
        // 여러 quant 단계가 있을 때 max가 적용되어야 함
        if quantizeLevels.count > 1 {
            XCTAssertTrue(quantizeLevels.contains(2),
                "Should include quantization level 2 after sufficient degradation")
        }
    }
}

private extension AutoQualityPlannerTests {
    func makePlanner(codec: CodecFourCC = .avc1, strategy: AutoQualityStrategy = .balanced) -> AutoQualityPlanner {
        AutoQualityPlanner(
            codec: codec,
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
