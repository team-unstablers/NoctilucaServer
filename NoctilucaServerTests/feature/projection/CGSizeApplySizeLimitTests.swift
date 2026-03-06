//
//  CGSizeApplySizeLimitTests.swift
//  NoctilucaServerTests
//
//  Created by Gyuhwan Park on 2/26/26.
//

import CoreGraphics
import XCTest

@testable import NoctilucaServerTestsHost

final class CGSizeApplySizeLimitTests: XCTestCase {
    // MARK: - desired가 원본보다 크거나 같은 경우

    func testReturnsOriginalWhenDesiredIsLarger() {
        let original = CGSize(width: 1920, height: 1080)
        let desired = CGSize(width: 3840, height: 2160)

        let result = original.applySizeLimit(desired)

        XCTAssertEqual(result.width, 1920)
        XCTAssertEqual(result.height, 1080)
    }

    func testReturnsOriginalWhenDesiredIsEqual() {
        let original = CGSize(width: 1920, height: 1080)
        let desired = CGSize(width: 1920, height: 1080)

        let result = original.applySizeLimit(desired)

        XCTAssertEqual(result.width, 1920)
        XCTAssertEqual(result.height, 1080)
    }

    // MARK: - desired가 원본보다 작은 경우 (축소)

    func testScalesDown16x9() {
        // 4K → 1080p 수준으로 축소
        let original = CGSize(width: 3840, height: 2160)
        let desired = CGSize(width: 1920, height: 1080)

        let result = original.applySizeLimit(desired)

        // 비율 유지 확인 (16:9)
        let originalRatio = original.width / original.height
        let resultRatio = result.width / result.height
        XCTAssertEqual(originalRatio, resultRatio, accuracy: 0.01)

        // 픽셀 수가 desired 이하인지 확인
        let resultPixels = result.width * result.height
        let desiredPixels = desired.width * desired.height
        XCTAssertLessThanOrEqual(resultPixels, desiredPixels)

        // 축소는 되었지만 지나치게 작아지지는 않았는지 확인
        XCTAssertGreaterThan(result.width, 0)
        XCTAssertGreaterThan(result.height, 0)
    }

    func testScalesDown4x3() {
        let original = CGSize(width: 2560, height: 1920)
        let desired = CGSize(width: 1280, height: 960)

        let result = original.applySizeLimit(desired)

        let originalRatio = original.width / original.height
        let resultRatio = result.width / result.height
        XCTAssertEqual(originalRatio, resultRatio, accuracy: 0.01)

        let resultPixels = result.width * result.height
        let desiredPixels = desired.width * desired.height
        XCTAssertLessThanOrEqual(resultPixels, desiredPixels)
    }

    func testScalesDownUltrawide() {
        // 21:9 비율
        let original = CGSize(width: 3440, height: 1440)
        let desired = CGSize(width: 1920, height: 1080)

        let result = original.applySizeLimit(desired)

        let originalRatio = original.width / original.height
        let resultRatio = result.width / result.height
        XCTAssertEqual(originalRatio, resultRatio, accuracy: 0.01)

        let resultPixels = result.width * result.height
        let desiredPixels = desired.width * desired.height
        XCTAssertLessThanOrEqual(resultPixels, desiredPixels)
    }

    // MARK: - 비율 보존 검증

    func testMaintainsAspectRatioOnSignificantDownscale() {
        // 4K → 480p 수준으로 큰 폭 축소
        let original = CGSize(width: 3840, height: 2160)
        let desired = CGSize(width: 720, height: 480)

        let result = original.applySizeLimit(desired)

        let originalRatio = original.width / original.height
        let resultRatio = result.width / result.height
        XCTAssertEqual(originalRatio, resultRatio, accuracy: 0.02)

        let resultPixels = result.width * result.height
        let desiredPixels = desired.width * desired.height
        XCTAssertLessThanOrEqual(resultPixels, desiredPixels)
    }

    // MARK: - desired 픽셀 수가 같지만 비율이 다른 경우

    func testDesiredDifferentAspectRatioSamePixelCount() {
        // 원본: 16:9, desired: 4:3 (비율은 다르지만 픽셀 수로 비교)
        let original = CGSize(width: 1920, height: 1080)
        // desired의 픽셀 수가 원본보다 작도록 설정
        let desired = CGSize(width: 1280, height: 960)

        let result = original.applySizeLimit(desired)

        // 원본 비율(16:9)이 유지되어야 함
        let originalRatio = original.width / original.height
        let resultRatio = result.width / result.height
        XCTAssertEqual(originalRatio, resultRatio, accuracy: 0.01)

        let resultPixels = result.width * result.height
        let desiredPixels = desired.width * desired.height
        XCTAssertLessThanOrEqual(resultPixels, desiredPixels)
    }
}
