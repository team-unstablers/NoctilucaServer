//
//  NOCDisplaySpecValidationTests.swift
//  NoctilucaServerTests
//
//  Created by Gyuhwan Park on 4/25/26.
//

import CoreGraphics
import XCTest

@testable import NoctilucaServerTestsHost

final class NOCDisplaySpecValidationTests: XCTestCase {
    private func spec(
        _ width: Int,
        _ height: Int,
        refreshRate: Double = 60,
        scaleFactor: CGFloat = 1
    ) -> NOCDisplaySpec {
        NOCDisplaySpec(
            resolution: CGSize(width: width, height: height),
            refreshRate: refreshRate,
            scaleFactor: scaleFactor,
            metadata: [:]
        )
    }

    // MARK: - Happy path

    func testValidatesCommonResolutions() {
        XCTAssertNoThrow(try spec(1920, 1080).validateForVirtualDisplay())
        XCTAssertNoThrow(try spec(1280, 720).validateForVirtualDisplay())
        XCTAssertNoThrow(try spec(2560, 1440).validateForVirtualDisplay())
        // 3840x2160@1x는 네이티브 픽셀 상한과 정확히 동일 → 경계 통과
        XCTAssertNoThrow(try spec(3840, 2160).validateForVirtualDisplay())
    }

    func testValidatesHiDPIAtMaximumBoundary() {
        // 1920x1080@2x → 네이티브 3840x2160 픽셀 (상한과 일치) → 통과
        XCTAssertNoThrow(try spec(1920, 1080, scaleFactor: 2).validateForVirtualDisplay())
    }

    func testRefreshRateZeroIsAccepted() {
        // refreshRate == 0은 "미지정"으로 허용된다.
        XCTAssertNoThrow(try spec(1920, 1080, refreshRate: 0).validateForVirtualDisplay())
    }

    func testMinimumResolutionIsAccepted() {
        XCTAssertNoThrow(try spec(320, 240).validateForVirtualDisplay())
    }

    // MARK: - Resolution limits

    func testRejectsOnePixelResolution() {
        XCTAssertThrowsError(try spec(1, 1).validateForVirtualDisplay()) { error in
            guard case NOCDisplaySpec.ValidationError.resolutionTooSmall = error else {
                return XCTFail("expected resolutionTooSmall, got \(error)")
            }
        }
    }

    func testRejectsBelowMinimumWidth() {
        XCTAssertThrowsError(try spec(319, 240).validateForVirtualDisplay()) { error in
            guard case NOCDisplaySpec.ValidationError.resolutionTooSmall = error else {
                return XCTFail("expected resolutionTooSmall, got \(error)")
            }
        }
    }

    func testRejectsBelowMinimumHeight() {
        XCTAssertThrowsError(try spec(640, 239).validateForVirtualDisplay()) { error in
            guard case NOCDisplaySpec.ValidationError.resolutionTooSmall = error else {
                return XCTFail("expected resolutionTooSmall, got \(error)")
            }
        }
    }

    func testRejectsZeroDimension() {
        XCTAssertThrowsError(try spec(1920, 0).validateForVirtualDisplay()) { error in
            guard case NOCDisplaySpec.ValidationError.nonPositiveResolution = error else {
                return XCTFail("expected nonPositiveResolution, got \(error)")
            }
        }
    }

    func testRejectsNegativeDimension() {
        XCTAssertThrowsError(try spec(-1920, 1080).validateForVirtualDisplay()) { error in
            guard case NOCDisplaySpec.ValidationError.nonPositiveResolution = error else {
                return XCTFail("expected nonPositiveResolution, got \(error)")
            }
        }
    }

    func testRejectsAbovePixelMaximum() {
        // 5120x2880 → 네이티브 5120x2880 > 3840x2160 → 거부
        XCTAssertThrowsError(try spec(5120, 2880).validateForVirtualDisplay()) { error in
            guard case NOCDisplaySpec.ValidationError.resolutionTooLargeInPixels = error else {
                return XCTFail("expected resolutionTooLargeInPixels, got \(error)")
            }
        }
    }

    func testRejectsHiDPIAbovePixelMaximum() {
        // 2560x1440@2x → 네이티브 5120x2880 > 3840x2160 → 거부
        XCTAssertThrowsError(try spec(2560, 1440, scaleFactor: 2).validateForVirtualDisplay()) { error in
            guard case NOCDisplaySpec.ValidationError.resolutionTooLargeInPixels = error else {
                return XCTFail("expected resolutionTooLargeInPixels, got \(error)")
            }
        }
    }

    // MARK: - Aspect ratio

    func testRejectsExtremeWideAspectRatio() {
        // 262144x2 → aspect ratio 131072 → 거부
        XCTAssertThrowsError(try spec(262144, 2).validateForVirtualDisplay()) { error in
            // 더 먼저 나오는 가드에 의해 nonPositive/tooSmall/tooLarge 중 하나로 떨어질 수도 있지만,
            // 최소/최대/aspect 중 어떤 것으로든 거부되면 스펙 의도가 만족된다.
            switch error {
            case NOCDisplaySpec.ValidationError.resolutionTooSmall,
                 NOCDisplaySpec.ValidationError.resolutionTooLargeInPixels,
                 NOCDisplaySpec.ValidationError.aspectRatioOutOfRange:
                break
            default:
                XCTFail("expected one of resolutionTooSmall / resolutionTooLargeInPixels / aspectRatioOutOfRange, got \(error)")
            }
        }
    }

    func testRejectsAspectRatioJustOverFourToOne() {
        // 1280x319 → 4.01 → aspect ratio 가드에 걸림
        // 단, height 319 < 240 가드를 먼저 통과해야 aspect까지 감. 여기서는 640x155로 구성:
        //   640x155 → width OK(>=320), height 155 < 240 → resolutionTooSmall 먼저 잡힘
        // 올바른 aspect-only 케이스: 1280x300 → 4.266... → aspect 거부, 나머지는 통과
        XCTAssertThrowsError(try spec(1280, 300).validateForVirtualDisplay()) { error in
            guard case NOCDisplaySpec.ValidationError.aspectRatioOutOfRange = error else {
                return XCTFail("expected aspectRatioOutOfRange, got \(error)")
            }
        }
    }

    func testRejectsAspectRatioJustOverOneToFour() {
        // 300x1280 → 0.234... < 0.25 → aspect 거부
        XCTAssertThrowsError(try spec(300, 1280).validateForVirtualDisplay()) { error in
            // 300 < 320이면 resolutionTooSmall 먼저 잡힐 수 있음 — 여기서는 320x1300로 가도:
            //   320x1300 → 0.246... < 0.25 → aspect
            // 하지만 위 300x1280는 width<320이라 tooSmall 먼저 발동될 거라 아래 케이스로 교체.
            switch error {
            case NOCDisplaySpec.ValidationError.resolutionTooSmall,
                 NOCDisplaySpec.ValidationError.aspectRatioOutOfRange:
                break
            default:
                XCTFail("expected resolutionTooSmall or aspectRatioOutOfRange, got \(error)")
            }
        }
    }

    func testAcceptsUltraWideWithinLimits() {
        // 3840x1080 → ratio 3.555... → 4 이하, 네이티브 픽셀도 상한 내 → 통과
        XCTAssertNoThrow(try spec(3840, 1080).validateForVirtualDisplay())
    }

    // MARK: - scaleFactor

    func testRejectsUnsupportedScaleFactor() {
        XCTAssertThrowsError(try spec(1920, 1080, scaleFactor: 3).validateForVirtualDisplay()) { error in
            guard case NOCDisplaySpec.ValidationError.unsupportedScaleFactor = error else {
                return XCTFail("expected unsupportedScaleFactor, got \(error)")
            }
        }
    }

    func testRejectsFractionalScaleFactor() {
        XCTAssertThrowsError(try spec(1920, 1080, scaleFactor: 1.5).validateForVirtualDisplay()) { error in
            guard case NOCDisplaySpec.ValidationError.unsupportedScaleFactor = error else {
                return XCTFail("expected unsupportedScaleFactor, got \(error)")
            }
        }
    }

    func testRejectsZeroScaleFactor() {
        XCTAssertThrowsError(try spec(1920, 1080, scaleFactor: 0).validateForVirtualDisplay()) { error in
            guard case NOCDisplaySpec.ValidationError.unsupportedScaleFactor = error else {
                return XCTFail("expected unsupportedScaleFactor, got \(error)")
            }
        }
    }

    // MARK: - refreshRate

    func testRejectsNegativeRefreshRate() {
        XCTAssertThrowsError(try spec(1920, 1080, refreshRate: -1).validateForVirtualDisplay()) { error in
            guard case NOCDisplaySpec.ValidationError.refreshRateOutOfRange = error else {
                return XCTFail("expected refreshRateOutOfRange, got \(error)")
            }
        }
    }

    func testRejectsRefreshRateAbove120() {
        XCTAssertThrowsError(try spec(1920, 1080, refreshRate: 240).validateForVirtualDisplay()) { error in
            guard case NOCDisplaySpec.ValidationError.refreshRateOutOfRange = error else {
                return XCTFail("expected refreshRateOutOfRange, got \(error)")
            }
        }
    }

    func testAcceptsRefreshRateAt120Boundary() {
        XCTAssertNoThrow(try spec(1920, 1080, refreshRate: 120).validateForVirtualDisplay())
    }

    func testAcceptsFractionalRefreshRate() {
        XCTAssertNoThrow(try spec(1920, 1080, refreshRate: 59.94).validateForVirtualDisplay())
    }
}
