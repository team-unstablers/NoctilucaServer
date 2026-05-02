//
//  MouseAccelerationProfile.swift
//  NoctilucaClient
//
//  Relative pointer delta에 적용하는 가속도 프로파일.
//  NoctilucaClientQt의 동일 모듈을 수식/상수 그대로 이식.
//

import Foundation

enum MouseAccelerationMode: String, Codable, CaseIterable, Sendable {
    case off
    case flat
    case adaptive

    init(from decoder: any Decoder) throws {
        let container = try? decoder.singleValueContainer()
        let rawValue = (try? container?.decode(String.self)) ?? Self.adaptive.rawValue
        self = MouseAccelerationMode(rawValue: rawValue) ?? .adaptive
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct AcceleratedDelta {
    var dx: Double
    var dy: Double
}

protocol MouseAccelerationProfile: AnyObject {
    /// Raw delta에 가속도를 적용한 결과를 반환합니다.
    /// - Parameters:
    ///   - dx: 원본 가로 델타
    ///   - dy: 원본 세로 델타
    ///   - timestampUs: 이벤트 타임스탬프 (µs)
    func accelerate(dx: Double, dy: Double, timestampUs: UInt64) -> AcceleratedDelta

    /// 감도 [-1.0, 1.0]. 0.0이 기본.
    func setSensitivity(_ sensitivity: Double)

    /// 내부 상태를 초기화합니다.
    func reset()
}

enum MouseAccelerationProfileFactory {
    static func make(mode: MouseAccelerationMode, sensitivity: Double) -> MouseAccelerationProfile {
        switch mode {
        case .off:
            return OffAccelerationProfile()
        case .flat:
            let profile = FlatAccelerationProfile()
            profile.setSensitivity(sensitivity)
            return profile
        case .adaptive:
            let profile = AdaptiveAccelerationProfile()
            profile.setSensitivity(sensitivity)
            return profile
        }
    }
}

// MARK: - Off

final class OffAccelerationProfile: MouseAccelerationProfile {
    func accelerate(dx: Double, dy: Double, timestampUs: UInt64) -> AcceleratedDelta {
        AcceleratedDelta(dx: dx, dy: dy)
    }

    func setSensitivity(_ sensitivity: Double) {}

    func reset() {}
}

// MARK: - Flat

final class FlatAccelerationProfile: MouseAccelerationProfile {
    private var multiplier: Double = 1.0

    func accelerate(dx: Double, dy: Double, timestampUs: UInt64) -> AcceleratedDelta {
        AcceleratedDelta(dx: dx * multiplier, dy: dy * multiplier)
    }

    func setSensitivity(_ sensitivity: Double) {
        // sensitivity [-1.0, 1.0] -> multiplier [0.25, 4.0]
        // pow(4.0, 0) = 1.0, pow(4.0, -1) = 0.25, pow(4.0, 1) = 4.0
        let clamped = max(-1.0, min(1.0, sensitivity))
        multiplier = pow(4.0, clamped)
    }

    func reset() {}
}

// MARK: - Adaptive

final class AdaptiveAccelerationProfile: MouseAccelerationProfile {
    private static let velocityLow: Double = 200.0
    private static let velocityHigh: Double = 2000.0
    private static let factorMin: Double = 1.0
    private static let factorMax: Double = 3.5
    private static let gapThresholdUs: UInt64 = 300_000
    private static let trackerSize: Int = 4

    private var sensitivityMultiplier: Double = 1.0
    private var lastTimestampUs: UInt64 = 0
    private var hasLastTimestamp: Bool = false
    private var lastFactor: Double = 1.0

    private var velocityHistory: [Double] = Array(repeating: 0.0, count: AdaptiveAccelerationProfile.trackerSize)
    private var velocityHistoryIndex: Int = 0
    private var velocityHistoryCount: Int = 0

    func accelerate(dx: Double, dy: Double, timestampUs: UInt64) -> AcceleratedDelta {
        var factor = lastFactor

        if hasLastTimestamp && timestampUs > lastTimestampUs {
            let dtUs = timestampUs - lastTimestampUs

            if dtUs > Self.gapThresholdUs {
                // 300ms 이상 갭 → 트래커 초기화, factor = 1.0
                reset()
                factor = Self.factorMin
            } else {
                let dtSeconds = Double(dtUs) / 1_000_000.0
                let distance = hypot(dx, dy)
                let velocity = distance / dtSeconds
                let smoothed = computeSmoothedVelocity(velocity)
                factor = Self.accelerationFactor(smoothed) * sensitivityMultiplier
            }
        } else {
            // 첫 이벤트 혹은 동일 타임스탬프
            factor = Self.factorMin * sensitivityMultiplier
        }

        hasLastTimestamp = true
        lastTimestampUs = timestampUs
        lastFactor = factor

        return AcceleratedDelta(dx: dx * factor, dy: dy * factor)
    }

    func setSensitivity(_ sensitivity: Double) {
        // sensitivity [-1.0, 1.0] -> multiplier [0.5, 2.0]
        // pow(2.0, 0) = 1.0, pow(2.0, -1) = 0.5, pow(2.0, 1) = 2.0
        let clamped = max(-1.0, min(1.0, sensitivity))
        sensitivityMultiplier = pow(2.0, clamped)
    }

    func reset() {
        hasLastTimestamp = false
        lastTimestampUs = 0
        lastFactor = 1.0
        velocityHistoryIndex = 0
        velocityHistoryCount = 0
        for i in 0..<velocityHistory.count {
            velocityHistory[i] = 0.0
        }
    }

    private func computeSmoothedVelocity(_ velocity: Double) -> Double {
        velocityHistory[velocityHistoryIndex] = velocity
        velocityHistoryIndex = (velocityHistoryIndex + 1) % Self.trackerSize
        if velocityHistoryCount < Self.trackerSize {
            velocityHistoryCount += 1
        }

        // oldest → newest 순으로 i=1..count 가중치 부여
        var weightedSum: Double = 0.0
        var weightTotal: Double = 0.0

        for i in 0..<velocityHistoryCount {
            let idx = (velocityHistoryIndex - velocityHistoryCount + i + Self.trackerSize) % Self.trackerSize
            let weight = Double(i + 1)
            weightedSum += velocityHistory[idx] * weight
            weightTotal += weight
        }

        return weightTotal > 0.0 ? (weightedSum / weightTotal) : velocity
    }

    private static func accelerationFactor(_ velocity: Double) -> Double {
        if velocity <= velocityLow { return factorMin }
        if velocity >= velocityHigh { return factorMax }
        let t = (velocity - velocityLow) / (velocityHigh - velocityLow)
        return factorMin + t * (factorMax - factorMin)
    }
}
