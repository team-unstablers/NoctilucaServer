//
//  AutoQualityPlannerTests.swift
//  NoctilucaServerTests
//
//  Created by Coding Assistant on 12/18/25.
//

import XCTest
import CoreGraphics
import SiriusKit
@testable import NoctilucaServerTestsHost

/// `AutoQualityPlanner`는 `QualityPlanner` 프로토콜 계약을 이행하는
/// 구체 구현이다. 본 테스트는 **프로토콜 계약과 문서화된 의도**를
/// 기준으로 검증한다 — 알고리즘 내부 파라미터(emaAlpha, cooldownWindow,
/// threshold 값 등)는 명세가 아니므로 직접 값을 박아두지 않고, "조건이
/// 충족될 때까지 feed" 패턴으로 수렴 상한을 제공한다.
final class AutoQualityPlannerTests: XCTestCase {

    // MARK: - Preset (순수 함수)

    // Preset의 switch band는 4:3 비율의 pixelCount 기준으로 구성되어 있다
    // (AutoQualityPreset의 `CodecResolutionLevel.*.pixelCount` 사용 — 코드 주석 참조).
    // 따라서 각 band를 명확히 지정하려면 4:3 해상도로 테스트해야 한다.
    // 예: 1920×1080(16:9) = 2,073,600 픽셀은 hd720p(1,228,800) ≤ x < hd1080p(2,764,800)
    //     이므로 "720p~1080p" band(= target 4000)에 속한다 — 이는 설계상 의도된 동작.

    func testPresetH264ReturnsBandSpecificValues() {
        // Band 1: [0, sd480p)
        XCTAssertEqual(
            AutoQualityPreset.preset(for: .avc1, resolution: CGSize(width: 320, height: 240), frameRate: 60).targetBitrateKbps,
            500)
        // Band 2: [sd480p, hd720p)
        XCTAssertEqual(
            AutoQualityPreset.preset(for: .avc1, resolution: CGSize(width: 1024, height: 768), frameRate: 60).targetBitrateKbps,
            1_500)
        // Band 3: [hd720p, hd1080p)
        XCTAssertEqual(
            AutoQualityPreset.preset(for: .avc1, resolution: CGSize(width: 1600, height: 1200), frameRate: 60).targetBitrateKbps,
            4_000)
        // Band 4: [hd1080p, hd2k)
        XCTAssertEqual(
            AutoQualityPreset.preset(for: .avc1, resolution: CGSize(width: 2048, height: 1536), frameRate: 60).targetBitrateKbps,
            8_000)
        // Band 5: [hd2k, hd4k)
        XCTAssertEqual(
            AutoQualityPreset.preset(for: .avc1, resolution: CGSize(width: 3200, height: 2400), frameRate: 60).targetBitrateKbps,
            12_000)
        // Band 6: [hd4k, ∞)
        XCTAssertEqual(
            AutoQualityPreset.preset(for: .avc1, resolution: CGSize(width: 4096, height: 3072), frameRate: 60).targetBitrateKbps,
            18_000)
    }

    func testPresetHEVCReturnsBandSpecificValues() {
        XCTAssertEqual(
            AutoQualityPreset.preset(for: .hvc1, resolution: CGSize(width: 320, height: 240), frameRate: 60).targetBitrateKbps,
            300)
        XCTAssertEqual(
            AutoQualityPreset.preset(for: .hvc1, resolution: CGSize(width: 1024, height: 768), frameRate: 60).targetBitrateKbps,
            800)
        XCTAssertEqual(
            AutoQualityPreset.preset(for: .hvc1, resolution: CGSize(width: 1600, height: 1200), frameRate: 60).targetBitrateKbps,
            2_500)
        XCTAssertEqual(
            AutoQualityPreset.preset(for: .hvc1, resolution: CGSize(width: 2048, height: 1536), frameRate: 60).targetBitrateKbps,
            5_000)
        XCTAssertEqual(
            AutoQualityPreset.preset(for: .hvc1, resolution: CGSize(width: 3200, height: 2400), frameRate: 60).targetBitrateKbps,
            10_000)
        XCTAssertEqual(
            AutoQualityPreset.preset(for: .hvc1, resolution: CGSize(width: 4096, height: 3072), frameRate: 60).targetBitrateKbps,
            15_000)
    }

    func testPresetUnknownCodecFallsBackToH264() {
        let resolution = CGSize(width: 1920, height: 1080)
        let fps: Float = 60
        let h264 = AutoQualityPreset.preset(for: .avc1, resolution: resolution, frameRate: fps)

        // 0.9.10에서 제거된 코덱 (zrle/mjpg/webp) 및 임의 unknown FourCC.
        // negotiation 단계에서 reject 되어야 하지만, 우회 경로로 들어오더라도
        // preset 결정은 안전하게 H.264 로 fallback 되어야 한다 (회귀 방지).
        let unknownCodecs: [CodecFourCC] = [
            .mjpg, .webp, .zrle,
            CodecFourCC("X", "X", "X", "X"),
        ]
        for codec in unknownCodecs {
            let preset = AutoQualityPreset.preset(for: codec, resolution: resolution, frameRate: fps)
            XCTAssertEqual(preset.targetBitrateKbps, h264.targetBitrateKbps,
                           "Unknown codec \(codec.stringRepresentation) should fall back to H.264 preset")
            XCTAssertEqual(preset.maxBitrateKbps, h264.maxBitrateKbps)
        }
    }

    func testPresetVP8ReturnsBandSpecificValues() {
        // VP8은 H.264 대비 압축 효율이 떨어져 band별로 1.3~1.5배의 비트레이트가
        // 필요하다 — 사무용 핵심 구간(1080p~2K)은 1.5배, 양 끝(저해상도/4K)은 1.3배.
        // Band 1: [0, sd480p)
        XCTAssertEqual(
            AutoQualityPreset.preset(for: .vp80, resolution: CGSize(width: 320, height: 240), frameRate: 60).targetBitrateKbps,
            650)
        // Band 2: [sd480p, hd720p)
        XCTAssertEqual(
            AutoQualityPreset.preset(for: .vp80, resolution: CGSize(width: 1024, height: 768), frameRate: 60).targetBitrateKbps,
            1_950)
        // Band 3: [hd720p, hd1080p)
        XCTAssertEqual(
            AutoQualityPreset.preset(for: .vp80, resolution: CGSize(width: 1600, height: 1200), frameRate: 60).targetBitrateKbps,
            6_000)
        // Band 4: [hd1080p, hd2k)
        XCTAssertEqual(
            AutoQualityPreset.preset(for: .vp80, resolution: CGSize(width: 2048, height: 1536), frameRate: 60).targetBitrateKbps,
            12_000)
        // Band 5: [hd2k, hd4k)
        XCTAssertEqual(
            AutoQualityPreset.preset(for: .vp80, resolution: CGSize(width: 3200, height: 2400), frameRate: 60).targetBitrateKbps,
            15_600)
        // Band 6: [hd4k, ∞)
        XCTAssertEqual(
            AutoQualityPreset.preset(for: .vp80, resolution: CGSize(width: 4096, height: 3072), frameRate: 60).targetBitrateKbps,
            23_400)
    }

    func testPresetVP8IsAtLeastH264ForSameResolution() {
        // VP8은 동일 해상도에서 H.264보다 항상 비트레이트가 같거나 높아야 한다
        // (libvpx의 압축 효율이 VT H.264보다 낮음 — 화질을 맞추려면 더 많은 비트가 필요).
        let fps: Float = 60
        let resolutions: [CGSize] = [
            CGSize(width: 320, height: 240),
            CGSize(width: 854, height: 480),
            CGSize(width: 1280, height: 720),
            CGSize(width: 1920, height: 1080),
            CGSize(width: 2560, height: 1440),
            CGSize(width: 3840, height: 2160)
        ]
        for res in resolutions {
            let h264 = AutoQualityPreset.preset(for: .avc1, resolution: res, frameRate: fps)
            let vp8 = AutoQualityPreset.preset(for: .vp80, resolution: res, frameRate: fps)
            XCTAssertGreaterThanOrEqual(vp8.targetBitrateKbps, h264.targetBitrateKbps,
                                        "VP8 target should be ≥ H.264 target at \(res)")
            XCTAssertGreaterThanOrEqual(vp8.maxBitrateKbps, h264.maxBitrateKbps,
                                        "VP8 max should be ≥ H.264 max at \(res)")
        }
    }

    func testPresetHEVCIsAtMostH264ForSameResolution() {
        let fps: Float = 60
        let resolutions: [CGSize] = [
            CGSize(width: 320, height: 240),
            CGSize(width: 854, height: 480),
            CGSize(width: 1280, height: 720),
            CGSize(width: 1920, height: 1080),
            CGSize(width: 2560, height: 1440),
            CGSize(width: 3840, height: 2160)
        ]
        for res in resolutions {
            let h264 = AutoQualityPreset.preset(for: .avc1, resolution: res, frameRate: fps)
            let hevc = AutoQualityPreset.preset(for: .hvc1, resolution: res, frameRate: fps)
            XCTAssertLessThanOrEqual(hevc.targetBitrateKbps, h264.targetBitrateKbps,
                                     "HEVC target should be ≤ H.264 target at \(res)")
            XCTAssertLessThanOrEqual(hevc.maxBitrateKbps, h264.maxBitrateKbps,
                                     "HEVC max should be ≤ H.264 max at \(res)")
        }
    }

    func testPresetBoundaryPixelCountPicksUpperBandExclusive() {
        // 구현의 switch는 `..<`(exclusive upper) 를 사용한다 — 경계값 자체는 상위 band에 속함.
        let fps: Float = 60
        // 정확히 sd480p.pixelCount (= 720*480) 인 해상도는 상위(720p) band에 속해야 함.
        let atSD480 = AutoQualityPreset.preset(for: .avc1, resolution: CGSize(width: 720, height: 480), frameRate: fps)
        XCTAssertEqual(atSD480.targetBitrateKbps, 1_500,
                       "At the sd480p boundary the preset should pick the next (720p) band")
    }

    // MARK: - Initial State

    func testInitialBitrateUsesPresetAndNoDegradation() async throws {
        let resolution = CGSize(width: 1920, height: 1080)
        let fps: Float = 60
        let preset = AutoQualityPreset.preset(for: .avc1, resolution: resolution, frameRate: fps)

        let planner = await AutoQualityPlanner(codec: .avc1, resolution: resolution, frameRate: fps, strategy: .balanced)

        let targetBitrate = await planner.targetBitrateKbps()
        let maxBitrate = await planner.maxBitrateKbps()
        let degradations = await planner.plannedDegradations()
        XCTAssertEqual(targetBitrate, preset.targetBitrateKbps)
        XCTAssertEqual(maxBitrate, preset.maxBitrateKbps)
        XCTAssertTrue(degradations.isEmpty)
    }

    func testInitialStateAllowsDegradationByDefault() async throws {
        let planner = await makePlanner()
        let allow = await planner.allowDegradation
        XCTAssertTrue(allow)
    }

    // MARK: - Gating (allowDegradation)

    func testAllowDegradationFalseReturnsEmptyPlan() async throws {
        let planner = await makePlanner()
        // 먼저 일정량 누적
        await planner.feed(queuePressure: 1.0) // emergency → 2 steps accumulated
        let degradedCount = await planner.plannedDegradations().count
        XCTAssertGreaterThan(degradedCount, 0)

        // 이제 게이트를 닫음
        await planner.setAllowDegradation(false)
        let gatedCount = await planner.plannedDegradations().count
        XCTAssertEqual(gatedCount, 0,
                       "allowDegradation=false 시 plannedDegradations()는 빈 배열을 반환해야 함")
    }

    func testAllowDegradationToggleRevealsAndRehidesSteps() async throws {
        let planner = await makePlanner()
        await planner.feed(queuePressure: 1.0) // 누적
        let openedCount = await planner.plannedDegradations().count
        XCTAssertGreaterThan(openedCount, 0)

        await planner.setAllowDegradation(false)
        let closed = await planner.plannedDegradations().count
        XCTAssertEqual(closed, 0)

        await planner.setAllowDegradation(true)
        let reopenedCount = await planner.plannedDegradations().count
        XCTAssertEqual(reopenedCount, openedCount,
                       "토글 시 이전에 누적된 step이 동일하게 다시 노출되어야 함")
    }

    // MARK: - Strategy Switching (updateStrategy)

    func testUpdateStrategyChangesDegradationStepComposition() async throws {
        // .qualityFirst는 frameRate 우선(첫 스텝이 .lowerFrameRate)
        let planner = await makePlanner(strategy: .balanced)
        // balanced로 시작 → 첫 스텝은 .lowerQuality
        await planner.feed(queuePressure: 1.0)
        let balancedSteps = await planner.plannedDegradations()
        XCTAssertFalse(balancedSteps.isEmpty)
        if case .lowerQuality = balancedSteps[0] {
            // 기대대로
        } else {
            XCTFail("balanced의 첫 step은 .lowerQuality여야 함 (현재: \(balancedSteps[0]))")
        }

        // .qualityFirst로 전환 후 같은 degradationIndex에서 조회
        await planner.updateStrategy(.qualityFirst)
        let qualitySteps = await planner.plannedDegradations()
        XCTAssertFalse(qualitySteps.isEmpty)
        if case .lowerFrameRate = qualitySteps[0] {
            // 기대대로
        } else {
            XCTFail(".qualityFirst의 첫 step은 .lowerFrameRate여야 함 (현재: \(qualitySteps[0]))")
        }
    }

    func testUpdateStrategySameStrategyIsNoop() async throws {
        let planner = await makePlanner(strategy: .balanced)
        await planner.feed(queuePressure: 1.0)
        let stepsBefore = await planner.plannedDegradations()

        await planner.updateStrategy(.balanced)
        let stepsAfter = await planner.plannedDegradations()
        XCTAssertEqual(stepsBefore.count, stepsAfter.count,
                       "동일 strategy 재설정은 관찰 가능한 변화를 만들지 않아야 함")
    }

    // MARK: - Score-Based Adjustment (일반 경로)

    func testSingleBurstOfModerateDropIsSuppressedByEMA() async throws {
        // 단일 moderate drop(예: 0.10)은 즉시 degrade를 유발하지 않아야 한다.
        // — dropThreshold(0.05) 이상이지만 scoring이 아직 threshold(3)에 못 미침.
        let planner = await makePlanner()
        let baseCount = await planner.plannedDegradations().count

        await planner.feed(report: makeReport(dropRatio: 0.10))

        let count = await planner.plannedDegradations().count
        XCTAssertEqual(count, baseCount,
                       "single moderate drop burst는 즉시 degrade를 유발하지 않아야 함 (EMA/scoring으로 완충)")
    }

    func testSustainedMildDropEventuallyDegrades() async throws {
        let planner = await makePlanner()
        let ticks = await feedUntilDegraded(planner, source: .client, dropRatio: 0.08, maxTicks: 32)
        let count = await planner.plannedDegradations().count
        XCTAssertGreaterThan(count, 0,
                             "지속되는 mild drop은 유한한 tick 내 degrade를 유발해야 함 (\(ticks) ticks)")
    }

    func testFeedReportWithZeroReceivedDoesNotTriggerRecoveryAlone() async throws {
        let planner = await makePlanner()
        // 먼저 degrade 발생
        await planner.feed(queuePressure: 1.0)
        let afterDegrade = await planner.plannedDegradations().count
        XCTAssertGreaterThan(afterDegrade, 0)

        // received=0 리포트만 반복 — clientScore만 감소하므로 양쪽이 모두 stable하지 않음
        for _ in 0..<30 {
            await planner.feed(report: makeReport(received: 0, decoded: 0, dropped: 0, decodeMs: 0))
        }

        let afterReports = await planner.plannedDegradations().count
        XCTAssertEqual(afterReports, afterDegrade,
                       "received=0 리포트만으로는 회복이 일어나지 않아야 함 (serverScore 변화 없음)")
    }

    func testClientAndServerScoresAreIndependent() async throws {
        let planner = await makePlanner()

        // client 쪽에서 dropCritical 이상의 리포트를 누적
        await planner.feed(report: makeReport(dropRatio: 0.15))
        // server 쪽은 stable(감소)
        await planner.feed(queuePressure: 0.0)
        // client 쪽 또 bad 리포트
        await planner.feed(report: makeReport(dropRatio: 0.15))

        // 기존 "단일 점수" 방식이라면 server의 -1이 client의 가산을 상쇄했을 것.
        // 분리 점수 방식에서는 client만으로도 degrade가 발생해야 함.
        let degradations = await planner.plannedDegradations()
        XCTAssertFalse(degradations.isEmpty,
                       "client score가 임계치를 넘으면 server score 상태와 무관하게 degrade가 발생해야 함")
    }

    func testRecoveryRequiresBothSourcesStable() async throws {
        let planner = await makePlanner()
        // 먼저 degrade
        await planner.feed(queuePressure: 1.0)
        let afterDegrade = await planner.plannedDegradations().count
        XCTAssertGreaterThan(afterDegrade, 0)

        // client만 stable feed
        for _ in 0..<30 {
            await planner.feed(report: makeReport(received: 100, decoded: 100, dropped: 0, decodeMs: 3))
        }
        let afterClientOnly = await planner.plannedDegradations().count
        XCTAssertEqual(afterClientOnly, afterDegrade,
                       "client만 stable해서는 회복이 일어나지 않아야 함")

        // 양쪽 stable feed — 유한 tick 내 완전 회복
        let recovered = await feedUntilRecovered(planner, maxTicks: 64)
        XCTAssertTrue(recovered, "양쪽 stable feed로 회복이 일어나야 함 (maxTicks=64)")

        let afterBoth = await planner.plannedDegradations().count
        XCTAssertEqual(afterBoth, 0,
                       "완전 회복 후 plannedDegradations는 빈 배열이어야 함")
    }

    func testDegradationAddsStepAndLowersBitrate() async throws {
        let planner = await makePlanner()
        let baselineTarget = await planner.targetBitrateKbps()
        let baselineSteps = await planner.plannedDegradations().count

        // sustained bad reports (magic number로 횟수를 박지 않고, 변화가 관찰될 때까지)
        let ticks = await feedUntilDegraded(planner, source: .client, dropRatio: 0.20, maxTicks: 16)
        XCTAssertLessThan(ticks, 16, "dropRatio=0.20 지속 시 16 tick 내 degrade가 발생해야 함")

        let newTarget = await planner.targetBitrateKbps()
        let newSteps = await planner.plannedDegradations().count
        XCTAssertLessThan(newTarget, baselineTarget)
        XCTAssertGreaterThan(newSteps, baselineSteps)
    }

    // MARK: - Emergency Path

    func testEmergencyDropRatioTriggersImmediateCriticalDegrade() async throws {
        let planner = await makePlanner()
        let baselineTarget = await planner.targetBitrateKbps()

        // dropRatio >= emergencyDropThreshold(명세상 "드랍 30% 이상") → 즉시 critical
        await planner.feed(report: makeReport(dropRatio: 0.50))

        let newTarget = await planner.targetBitrateKbps()
        let steps = await planner.plannedDegradations().count
        XCTAssertLessThan(newTarget, baselineTarget)
        XCTAssertGreaterThanOrEqual(steps, 2,
                                    "emergency drop은 critical degrade로 최소 2 step을 전진시켜야 함")
    }

    func testEmergencyQueuePressureTriggersImmediateCriticalDegrade() async throws {
        let planner = await makePlanner()
        let baselineTarget = await planner.targetBitrateKbps()

        // queuePressure >= emergencyPressureThreshold → 즉시 critical
        await planner.feed(queuePressure: 1.0)

        let newTarget = await planner.targetBitrateKbps()
        let steps = await planner.plannedDegradations().count
        XCTAssertLessThan(newTarget, baselineTarget)
        XCTAssertGreaterThanOrEqual(steps, 2,
                                    "emergency pressure는 critical degrade로 최소 2 step을 전진시켜야 함")
    }

    func testEmergencyDuringCooldownDoesNotDoubleDegrade() async throws {
        let planner = await makePlanner()
        await planner.feed(queuePressure: 1.0) // 1st emergency
        let stepsAfterFirst = await planner.plannedDegradations().count

        // 곧바로 두 번째 emergency feed — cooldown이 추가 degrade를 막아야 함
        await planner.feed(queuePressure: 1.0)
        let stepsAfterSecond = await planner.plannedDegradations().count

        XCTAssertEqual(stepsAfterSecond, stepsAfterFirst,
                       "cooldown 중에는 emergency feed가 와도 추가 degrade가 일어나지 않아야 함")
    }

    // MARK: - Cooldown Window

    func testCooldownBlocksImmediateSecondDegrade() async throws {
        let planner = await makePlanner()
        await planner.feed(queuePressure: 1.0) // degrade → cooldown 시작
        let stepsA = await planner.plannedDegradations().count

        // 즉시 sustained bad reports (score path) — 여전히 cooldown 안이라면 degrade 안 됨
        await planner.feed(report: makeReport(dropRatio: 0.20))
        await planner.feed(report: makeReport(dropRatio: 0.20))
        let stepsB = await planner.plannedDegradations().count

        XCTAssertEqual(stepsB, stepsA,
                       "cooldown 직후 즉시 bad report가 와도 score 기반 degrade가 차단되어야 함")
    }

    func testCooldownEventuallyExpiresAllowingFurtherDegrade() async throws {
        let planner = await makePlanner()
        await planner.feed(queuePressure: 1.0) // 1st degrade
        let stepsA = await planner.plannedDegradations().count

        // 상한 내에서 emergency feed를 반복하다 보면 cooldown이 끝나고 다시 degrade가 가능해야 함
        var degradedAgain = false
        for _ in 0..<32 {
            await planner.feed(queuePressure: 1.0)
            let now = await planner.plannedDegradations().count
            if now > stepsA {
                degradedAgain = true
                break
            }
        }
        XCTAssertTrue(degradedAgain,
                      "cooldown이 만료된 뒤에는 emergency feed가 다시 degrade를 유발할 수 있어야 함 (maxTicks=32)")
    }

    // MARK: - Degradation Step Composition (코덱/전략별)

    func testBalancedDegradationIncludesQualityStep() async throws {
        let planner = await makePlanner(strategy: .balanced)
        await planner.feed(queuePressure: 1.0)

        let degradations = await planner.plannedDegradations()
        let hasQuality = degradations.contains { if case .lowerQuality = $0 { return true }; return false }
        XCTAssertTrue(hasQuality, "balanced 전략의 degradation step에는 .lowerQuality가 포함되어야 함")
    }

    func testCodecDegradationExcludesQuantization() async throws {
        // 0.9.10 에서 image codec (mjpg/zrle/webp) 가 제거되면서
        // .increaseQuantization 분기는 더 이상 plan 되지 않는다. 회귀 방지.
        for codec: CodecFourCC in [.avc1, .hvc1, .vp80] {
            let planner = await makePlanner(codec: codec, strategy: .balanced)
            await forceAllStepsActivated(planner, maxTicks: 32)

            let degradations = await planner.plannedDegradations()
            let hasQuantization = degradations.contains {
                if case .increaseQuantization = $0 { return true }; return false
            }
            XCTAssertFalse(hasQuantization,
                           "코덱 \(codec.stringRepresentation) 의 degradation step 에는 .increaseQuantization 이 포함되지 않아야 함")
        }
    }

    func testQualityFirstStrategyStartsWithFrameRateSteps() async throws {
        let planner = await makePlanner(strategy: .qualityFirst)
        await forceAllStepsActivated(planner, maxTicks: 32)

        let steps = await planner.plannedDegradations()
        XCTAssertGreaterThanOrEqual(steps.count, 2)
        // 첫 두 step이 .lowerFrameRate
        if case .lowerFrameRate = steps[0] {} else {
            XCTFail(".qualityFirst의 첫 step은 .lowerFrameRate여야 함 (현재: \(steps[0]))")
        }
        if case .lowerFrameRate = steps[1] {} else {
            XCTFail(".qualityFirst의 두 번째 step은 .lowerFrameRate여야 함 (현재: \(steps[1]))")
        }
    }

    func testPerformanceFirstStrategyEndsWithFrameRateSteps() async throws {
        let planner = await makePlanner(strategy: .performanceFirst)
        await forceAllStepsActivated(planner, maxTicks: 32)

        let steps = await planner.plannedDegradations()
        XCTAssertGreaterThanOrEqual(steps.count, 2)
        let lastTwo = steps.suffix(2)
        for step in lastTwo {
            if case .lowerFrameRate = step {} else {
                XCTFail(".performanceFirst의 마지막 두 step은 .lowerFrameRate여야 함 (현재: \(step))")
            }
        }
    }

    // MARK: - Multiplier Clamp

    func testMultiplierClampedAtMinAfterRepeatedDegrade() async throws {
        let planner = await makePlanner()
        let preset = AutoQualityPreset.preset(
            for: .avc1,
            resolution: CGSize(width: 1920, height: 1080),
            frameRate: 60)

        // 반복 degrade — multiplier는 `minMultiplier`(명세상 0.4) 밑으로 내려가지 않아야 함
        for _ in 0..<32 {
            await planner.feed(queuePressure: 1.0)
        }

        let target = await planner.targetBitrateKbps()
        let lowerBound = Int(Float(preset.targetBitrateKbps) * 0.4)
        // 정수 반올림 tolerance 1
        XCTAssertGreaterThanOrEqual(target, lowerBound - 1,
                                    "multiplier가 minMultiplier(0.4) 밑으로 떨어지지 않아야 함 — got \(target), bound \(lowerBound)")
    }

    func testMultiplierClampedAtMaxAfterRepeatedRecovery() async throws {
        let planner = await makePlanner()
        let preset = AutoQualityPreset.preset(
            for: .avc1,
            resolution: CGSize(width: 1920, height: 1080),
            frameRate: 60)

        // 충분한 양쪽 stable feed로 repeat recovery 발생 → multiplier 상승 → 1.5에서 클램프
        for _ in 0..<100 {
            await planner.feed(report: makeReport(received: 100, decoded: 100, dropped: 0, decodeMs: 3))
            await planner.feed(queuePressure: 0.0)
        }

        let target = await planner.targetBitrateKbps()
        let upperBound = Int(Float(preset.targetBitrateKbps) * 1.5)
        XCTAssertLessThanOrEqual(target, upperBound + 1,
                                 "multiplier가 maxMultiplier(1.5) 위로 올라가지 않아야 함 — got \(target), bound \(upperBound)")
    }

    // MARK: - Callback Events

    func testCallbackFiresOnDegradeWithMatchingFields() async throws {
        let planner = await makePlanner()
        let recorder = QualityEventRecorder()
        await planner.setOnQualityAdjustmentHandler { [recorder] event in
            recorder.record(event)
        }

        await planner.feed(queuePressure: 1.0) // emergency → critical degrade

        let events = recorder.snapshot()
        XCTAssertEqual(events.count, 1, "degrade 1회에 대해 콜백이 1회 발생해야 함")
        let event = try XCTUnwrap(events.first)
        XCTAssertDirection(event.direction, .degraded)
        XCTAssertTrigger(event.trigger, .networkThroughput)
        XCTAssertTrue(event.isCritical, "emergency pressure는 critical")

        let stepCount = await planner.plannedDegradations().count
        XCTAssertEqual(event.degradationIndex, stepCount,
                       "event.degradationIndex == plannedDegradations().count")
    }

    func testCallbackDegradeClientFeedbackTrigger() async throws {
        let planner = await makePlanner()
        let recorder = QualityEventRecorder()
        await planner.setOnQualityAdjustmentHandler { [recorder] event in
            recorder.record(event)
        }

        await planner.feed(report: makeReport(dropRatio: 0.50)) // emergency drop

        let events = recorder.snapshot()
        let event = try XCTUnwrap(events.first)
        XCTAssertTrigger(event.trigger, .clientFeedback)
        XCTAssertTrue(event.isCritical)
    }

    func testCallbackTriggerIsBothWhenBothScoresCrossTogether() async throws {
        // `.both` trigger는 `clientScore >= 3 && serverScore >= 3`이 동시에 만족될 때만
        // 발생한다. 동일한 `maybeAdjustPlan` 호출 시점에 두 점수가 함께 threshold를
        // 넘도록 1차 degrade의 cooldown 동안 양쪽 점수를 동시 누적시킨다.
        let planner = await makePlanner()
        let recorder = QualityEventRecorder()
        await planner.setOnQualityAdjustmentHandler { [recorder] event in
            recorder.record(event)
        }

        // Cycle 1: client-only로 첫 degrade를 유발 (trigger == .clientFeedback)
        // dropRatio 0.20 × 2 → clientScore=2 → 4, applyDegradation(.clientFeedback)
        await planner.feed(report: makeReport(dropRatio: 0.20))
        await planner.feed(report: makeReport(dropRatio: 0.20))

        // cooldown 동안(3 ticks) 양쪽 점수를 충분히 누적시킨다.
        // maybeAdjustPlan은 cooldown 동안 threshold 체크 없이 decrement만 하므로
        // 이 3번의 feed는 EMA/score만 업데이트하고 degrade를 유발하지 않는다.
        await planner.feed(queuePressure: 0.6)                    // cooldown 3→2, serverScore=2
        await planner.feed(report: makeReport(dropRatio: 0.20))   // cooldown 2→1, clientScore=2
        await planner.feed(queuePressure: 0.6)                    // cooldown 1→0, serverScore=4

        // cooldown이 막 끝난 직후의 feed에서 clientScore도 ≥3으로 밀어올린다.
        await planner.feed(report: makeReport(dropRatio: 0.20))   // clientScore=4, serverScore=4 → .both

        let events = recorder.snapshot()
        let bothEvents = events.filter {
            isSameDirection($0.direction, .degraded) && isSameTrigger($0.trigger, .both)
        }
        XCTAssertFalse(bothEvents.isEmpty,
                       "양쪽 점수가 동시에 threshold를 넘는 상황에서 trigger==.both인 degrade 이벤트가 발생해야 함")
    }

    func testCallbackFiresOnRecovery() async throws {
        let planner = await makePlanner()
        let recorder = QualityEventRecorder()
        await planner.setOnQualityAdjustmentHandler { [recorder] event in
            recorder.record(event)
        }

        // 먼저 degrade
        await planner.feed(queuePressure: 1.0)
        // 양쪽 stable로 recovery 유도
        _ = await feedUntilRecovered(planner, maxTicks: 64)

        let events = recorder.snapshot()
        let hasRecovered = events.contains { isSameDirection($0.direction, .recovered) }
        XCTAssertTrue(hasRecovered, "완전 회복 과정 중 .recovered 이벤트가 최소 1회 이상 발생해야 함")
    }
}

// MARK: - Helpers

private extension AutoQualityPlannerTests {
    func makePlanner(codec: CodecFourCC = .avc1, strategy: AutoQualityStrategy = .balanced) async -> AutoQualityPlanner {
        await AutoQualityPlanner(
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

    /// `received = 100` 기준으로 목표 dropRatio를 만든다.
    func makeReport(dropRatio: Float, decodeMs: UInt32 = 5) -> ProjectionPerformanceReport {
        let received: UInt32 = 100
        let dropped = UInt32((Float(received) * dropRatio).rounded())
        let decoded = received - dropped
        return makeReport(received: received, decoded: decoded, dropped: dropped, decodeMs: decodeMs)
    }

    enum FeedSource {
        case client
        case server
    }

    /// `maxTicks` 상한 내에서 degrade가 발생할 때까지 feed. 걸린 횟수를 반환.
    @discardableResult
    func feedUntilDegraded(
        _ planner: AutoQualityPlanner,
        source: FeedSource,
        dropRatio: Float = 0.08,
        pressure: Float = 0.6,
        maxTicks: Int = 32
    ) async -> Int {
        let baseline = await planner.plannedDegradations().count
        for i in 0..<maxTicks {
            switch source {
            case .client:
                await planner.feed(report: makeReport(dropRatio: dropRatio))
            case .server:
                await planner.feed(queuePressure: pressure)
            }
            let now = await planner.plannedDegradations().count
            if now > baseline {
                return i + 1
            }
        }
        return maxTicks
    }

    /// `maxTicks` 상한 내에서 완전 회복(plannedDegradations().isEmpty)될 때까지
    /// 양쪽 stable feed를 반복. 성공 여부를 반환.
    @discardableResult
    func feedUntilRecovered(_ planner: AutoQualityPlanner, maxTicks: Int = 64) async -> Bool {
        for _ in 0..<maxTicks {
            let now = await planner.plannedDegradations().count
            if now == 0 {
                return true
            }
            await planner.feed(report: makeReport(received: 100, decoded: 100, dropped: 0, decodeMs: 3))
            await planner.feed(queuePressure: 0.0)
        }
        let finalCount = await planner.plannedDegradations().count
        return finalCount == 0
    }

    /// 구성된 모든 degradation step이 활성화될 때까지 emergency pressure를 반복 feed.
    /// 개수 매직 넘버를 피하기 위해, `plannedDegradations().count`가 더 이상 증가하지
    /// 않을 때까지 루프(상한 포함).
    func forceAllStepsActivated(_ planner: AutoQualityPlanner, maxTicks: Int = 32) async {
        var lastCount = -1
        var stableStreak = 0
        for _ in 0..<maxTicks {
            await planner.feed(queuePressure: 1.0)
            let count = await planner.plannedDegradations().count
            if count == lastCount {
                stableStreak += 1
                if stableStreak >= 4 { break }
            } else {
                stableStreak = 0
                lastCount = count
            }
        }
    }
}

// MARK: - Event Recorder

/// Sendable 콜백 내부에서 이벤트를 누적하는 간단한 기록기.
/// NSLock로 스레드 안전성을 보장하고 `@unchecked Sendable`로 액터 경계를 건넌다.
private final class QualityEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _events: [QualityAdjustmentEvent] = []

    func record(_ event: QualityAdjustmentEvent) {
        lock.lock()
        defer { lock.unlock() }
        _events.append(event)
    }

    func snapshot() -> [QualityAdjustmentEvent] {
        lock.lock()
        defer { lock.unlock() }
        return _events
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        _events.removeAll()
    }
}

// MARK: - Assertion helpers
//
// `QualityAdjustmentEvent.Direction`과 `.Trigger`는 `Equatable`을 채택하지
// 않으므로 `XCTAssertEqual` 대신 pattern matching 기반 헬퍼를 사용한다.
// (테스트 전용 retroactive conformance는 모듈 경계 경고를 유발할 수 있음)

private func XCTAssertDirection(
    _ actual: QualityAdjustmentEvent.Direction,
    _ expected: QualityAdjustmentEvent.Direction,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if !isSameDirection(actual, expected) {
        XCTFail("expected \(expected) but got \(actual)", file: file, line: line)
    }
}

private func XCTAssertTrigger(
    _ actual: QualityAdjustmentEvent.Trigger,
    _ expected: QualityAdjustmentEvent.Trigger,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if !isSameTrigger(actual, expected) {
        XCTFail("expected \(expected) but got \(actual)", file: file, line: line)
    }
}

private func isSameDirection(
    _ a: QualityAdjustmentEvent.Direction,
    _ b: QualityAdjustmentEvent.Direction
) -> Bool {
    switch (a, b) {
    case (.degraded, .degraded), (.recovered, .recovered):
        return true
    default:
        return false
    }
}

private func isSameTrigger(
    _ a: QualityAdjustmentEvent.Trigger,
    _ b: QualityAdjustmentEvent.Trigger
) -> Bool {
    switch (a, b) {
    case (.clientFeedback, .clientFeedback),
         (.networkThroughput, .networkThroughput),
         (.both, .both):
        return true
    default:
        return false
    }
}
