//
//  ProjectionSessionResolutionScaleTests.swift
//  NoctilucaServerTests
//
//  Created by Gyuhwan Park on 4/26/26.
//

import CoreGraphics
import XCTest

@testable import NoctilucaServerTestsHost

/// `ProjectionSession.applyResolutionScale(_:scale:)`의 명세를 검증한다.
///
/// 명세:
/// - scale은 `[0.05, 1.0]`로 클램프된다.
/// - 결과 width/height는 4의 배수로 floor 정렬된다 (인코더 친화).
/// - 너무 작은 값으로 줄어드는 것을 막기 위해 최소 4픽셀을 보장한다.
final class ProjectionSessionResolutionScaleTests: XCTestCase {
    // MARK: - 기본 동작

    func testScaleOneReturnsOriginalSize() {
        let baseline = CGSize(width: 1920, height: 1080)
        let result = ProjectionSession.applyResolutionScale(baseline, scale: 1.0)

        XCTAssertEqual(result.width, 1920)
        XCTAssertEqual(result.height, 1080)
    }

    func testScaleHalfReturnsHalfSizeAligned() {
        let baseline = CGSize(width: 1920, height: 1080)
        let result = ProjectionSession.applyResolutionScale(baseline, scale: 0.5)

        // 1920 * 0.5 = 960 (이미 4의 배수)
        XCTAssertEqual(result.width, 960)
        // 1080 * 0.5 = 540 (이미 4의 배수)
        XCTAssertEqual(result.height, 540)
    }

    // MARK: - 4의 배수 정렬

    func testAlignsTo4PixelMultiplesViaFloor() {
        // 1920 * 0.85 = 1632 (이미 4의 배수)
        // 1080 * 0.85 = 918 → floor(918/4)*4 = 916
        let baseline = CGSize(width: 1920, height: 1080)
        let result = ProjectionSession.applyResolutionScale(baseline, scale: 0.85)

        XCTAssertEqual(result.width.truncatingRemainder(dividingBy: 4), 0)
        XCTAssertEqual(result.height.truncatingRemainder(dividingBy: 4), 0)
        XCTAssertEqual(result.width, 1632)
        XCTAssertEqual(result.height, 916)
    }

    func testAlignsOddDimensionsToFourMultiplesViaFloor() {
        // baseline 자체가 비정렬: 1023 * 0.7 = 716.1 → floor(716/4)*4 = 716
        let baseline = CGSize(width: 1023, height: 769)
        let result = ProjectionSession.applyResolutionScale(baseline, scale: 0.7)

        XCTAssertEqual(result.width.truncatingRemainder(dividingBy: 4), 0)
        XCTAssertEqual(result.height.truncatingRemainder(dividingBy: 4), 0)
        // 결과는 항상 baseline*scale 이하여야 한다 (floor 보장)
        XCTAssertLessThanOrEqual(result.width, CGFloat(1023) * 0.7)
        XCTAssertLessThanOrEqual(result.height, CGFloat(769) * 0.7)
    }

    // MARK: - Clamp 경계

    func testScaleAboveOneIsClampedToOne() {
        let baseline = CGSize(width: 1920, height: 1080)
        let result = ProjectionSession.applyResolutionScale(baseline, scale: 1.5)

        XCTAssertEqual(result.width, 1920)
        XCTAssertEqual(result.height, 1080)
    }

    func testScaleBelowMinimumIsClampedTo005() {
        // scale=0이어도 0.05로 클램프되어 원본의 5%까지만 줄어듦
        let baseline = CGSize(width: 1920, height: 1080)
        let result = ProjectionSession.applyResolutionScale(baseline, scale: 0.0)

        // 1920 * 0.05 = 96 (4의 배수)
        XCTAssertEqual(result.width, 96)
        // 1080 * 0.05 = 54 → floor(54/4)*4 = 52
        XCTAssertEqual(result.height, 52)
    }

    func testNegativeScaleIsClampedToMinimum() {
        let baseline = CGSize(width: 1920, height: 1080)
        let resultZero = ProjectionSession.applyResolutionScale(baseline, scale: 0.0)
        let resultNegative = ProjectionSession.applyResolutionScale(baseline, scale: -0.5)

        XCTAssertEqual(resultZero, resultNegative)
    }

    // MARK: - 최소 픽셀 가드

    func testEnforcesMinimumFourPixelsForVerySmallBaseline() {
        // 1픽셀짜리 baseline이라면 어떤 scale에서도 0이 아니라 4픽셀로 보장되어야 한다
        let baseline = CGSize(width: 1, height: 1)
        let result = ProjectionSession.applyResolutionScale(baseline, scale: 0.5)

        XCTAssertEqual(result.width, 4)
        XCTAssertEqual(result.height, 4)
    }
}
