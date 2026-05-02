//
//  NOCDisplaySpec+Validation.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 4/25/26.
//

import Foundation
import CoreGraphics

extension NOCDisplaySpec {
    /// 가상 디스플레이 생성에 사용될 spec의 유효성 검증 실패 원인.
    enum ValidationError: Error, Sendable, CustomStringConvertible {
        case resolutionTooSmall(width: Int, height: Int, minWidth: Int, minHeight: Int)
        case resolutionTooLargeInPixels(
            pixelWidth: Int,
            pixelHeight: Int,
            maxPixelWidth: Int,
            maxPixelHeight: Int
        )
        case nonPositiveResolution(width: Int, height: Int)
        case unsupportedScaleFactor(CGFloat, allowed: [CGFloat])
        case refreshRateOutOfRange(Double, maximum: Double)
        case aspectRatioOutOfRange(
            width: Int,
            height: Int,
            ratio: Double,
            minimum: Double,
            maximum: Double
        )

        var description: String {
            switch self {
            case let .resolutionTooSmall(w, h, minW, minH):
                return "resolution too small: \(w)x\(h) (minimum \(minW)x\(minH))"
            case let .resolutionTooLargeInPixels(pw, ph, maxPW, maxPH):
                return "native resolution too large: \(pw)x\(ph) pixels (maximum \(maxPW)x\(maxPH) pixels)"
            case let .nonPositiveResolution(w, h):
                return "resolution must be positive: got \(w)x\(h)"
            case let .unsupportedScaleFactor(s, allowed):
                let allowedStr = allowed.map { "\(Int($0))x" }.joined(separator: ", ")
                return "unsupported scaleFactor: \(s)x (allowed: \(allowedStr))"
            case let .refreshRateOutOfRange(rate, maximum):
                return "refreshRate out of range: \(rate)Hz (allowed: 0 or 0 < r <= \(maximum))"
            case let .aspectRatioOutOfRange(w, h, ratio, minimum, maximum):
                return String(
                    format: "aspect ratio out of range: %dx%d (ratio %.3f, allowed %.3f ~ %.3f)",
                    w, h, ratio, minimum, maximum
                )
            }
        }
    }

    /// 가드 정책 상수. 서버/헬퍼 양쪽에서 동일 값을 사용한다.
    enum ValidationPolicy {
        /// 각 차원의 최소 해상도(논리 점 단위).
        static let minWidth: Int = 320
        static let minHeight: Int = 240

        /// 네이티브 픽셀(=resolution × scaleFactor) 기준 최대 해상도.
        /// macOS CGVirtualDisplay가 안정적으로 수용하는 상한.
        static let maxPixelWidth: Int = 3840
        static let maxPixelHeight: Int = 2160

        /// 허용되는 scaleFactor 값 목록.
        static let allowedScaleFactors: [CGFloat] = [1, 2]

        /// refreshRate 상한(Hz). 0은 "미지정"을 의미하며 별도로 허용된다.
        static let maxRefreshRate: Double = 120

        /// Aspect ratio(가로/세로) 허용 범위.
        static let minAspectRatio: Double = 0.25
        static let maxAspectRatio: Double = 4.0
    }

    /// 가상 디스플레이 생성에 사용하기 전에 spec의 유효성을 검증한다.
    ///
    /// 검증 항목:
    /// - 해상도가 양의 정수일 것
    /// - 각 차원이 최소 해상도 이상일 것 (`320x240`)
    /// - 네이티브 픽셀 해상도(resolution × scaleFactor)가 상한을 넘지 않을 것 (`3840x2160` 픽셀)
    /// - scaleFactor가 허용된 값일 것 (`1x`, `2x`)
    /// - refreshRate가 범위 내일 것 (`0` 또는 `0 < r <= 120`)
    /// - Aspect ratio가 범위 내일 것 (1:4 ~ 4:1)
    func validateForVirtualDisplay() throws {
        let width = Int(resolution.width)
        let height = Int(resolution.height)

        guard width > 0, height > 0 else {
            throw ValidationError.nonPositiveResolution(width: width, height: height)
        }

        guard ValidationPolicy.allowedScaleFactors.contains(scaleFactor) else {
            throw ValidationError.unsupportedScaleFactor(
                scaleFactor,
                allowed: ValidationPolicy.allowedScaleFactors
            )
        }

        guard width >= ValidationPolicy.minWidth, height >= ValidationPolicy.minHeight else {
            throw ValidationError.resolutionTooSmall(
                width: width,
                height: height,
                minWidth: ValidationPolicy.minWidth,
                minHeight: ValidationPolicy.minHeight
            )
        }

        let pixelWidth = Int((resolution.width * scaleFactor).rounded())
        let pixelHeight = Int((resolution.height * scaleFactor).rounded())

        guard pixelWidth <= ValidationPolicy.maxPixelWidth,
              pixelHeight <= ValidationPolicy.maxPixelHeight
        else {
            throw ValidationError.resolutionTooLargeInPixels(
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                maxPixelWidth: ValidationPolicy.maxPixelWidth,
                maxPixelHeight: ValidationPolicy.maxPixelHeight
            )
        }

        if refreshRate != 0 {
            guard refreshRate > 0, refreshRate <= ValidationPolicy.maxRefreshRate else {
                throw ValidationError.refreshRateOutOfRange(
                    refreshRate,
                    maximum: ValidationPolicy.maxRefreshRate
                )
            }
        }

        let ratio = Double(resolution.width) / Double(resolution.height)
        guard ratio >= ValidationPolicy.minAspectRatio,
              ratio <= ValidationPolicy.maxAspectRatio
        else {
            throw ValidationError.aspectRatioOutOfRange(
                width: width,
                height: height,
                ratio: ratio,
                minimum: ValidationPolicy.minAspectRatio,
                maximum: ValidationPolicy.maxAspectRatio
            )
        }
    }
}
