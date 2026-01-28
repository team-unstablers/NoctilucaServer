//
//  FrameDropController.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/28/26.
//

import Foundation
import CoreMedia

/// 프레임 드랍 정책을 관리하는 컨트롤러
/// PTS 기반 드랍과 backpressure 기반 드랍을 별도 메서드로 제공
class FrameDropController {
    private let logger = NoctilucaLogger(category: "FrameDropController")

    // MARK: - PTS 드랍 상태
    private var currentFrameRate: Float = 60.0
    private var consecutivePtsDropCount: Int = 0
    private var needsKeyframeAfterPtsDrop: Bool = false
    private let ptsDropKeyframeThreshold: Int = 3

    // MARK: - Backpressure 드랍 상태
    private var flushAll: Bool = false

    func configure(frameRate: Float) {
        self.currentFrameRate = frameRate
    }

    /// PTS 기반 드랍 판정 (인코딩 전)
    /// - Returns: (shouldDrop: Bool, needsKeyframe: Bool)
    func shouldDropByPts(_ sampleBuffer: CMSampleBuffer) -> (shouldDrop: Bool, needsKeyframe: Bool) {
        let pts = sampleBuffer.presentationTimeStamp
        let systemNow = CMTime(value: Int64(mach_absolute_time()), timescale: 1_000_000_000)
        let latency = systemNow.seconds - pts.seconds

        // 음수 latency(미래 프레임)는 드랍하지 않음
        guard latency > 0 else {
            consecutivePtsDropCount = 0
            return (shouldDrop: false, needsKeyframe: consumeKeyframeRequest())
        }

        // frameRate 기반 동적 임계값: 2프레임분 지연 시 드랍
        let frameInterval = 1.0 / Double(max(currentFrameRate, 30))
        let threshold = frameInterval * 2.0

        if latency > threshold {
            consecutivePtsDropCount += 1
            logger.debug("Dropping frame due to PTS latency: \(latency)s (threshold: \(threshold)s, consecutive: \(consecutivePtsDropCount))")

            if consecutivePtsDropCount >= ptsDropKeyframeThreshold {
                needsKeyframeAfterPtsDrop = true
                consecutivePtsDropCount = 0
            }
            return (shouldDrop: true, needsKeyframe: false)
        }

        consecutivePtsDropCount = 0
        return (shouldDrop: false, needsKeyframe: consumeKeyframeRequest())
    }

    /// Backpressure 기반 드랍 판정 (인코딩 후)
    /// - Returns: (shouldDrop: Bool, needsKeyframe: Bool)
    func shouldDropByBackpressure(
        writeBackPressure: Int,
        maxBitrateKbps: Int
    ) -> (shouldDrop: Bool, needsKeyframe: Bool) {
        if flushAll {
            if writeBackPressure == 0 {
                flushAll = false
                return (shouldDrop: true, needsKeyframe: true)
            }
            logger.info("Flushing frame due to backpressure")
            return (shouldDrop: true, needsKeyframe: false)
        }

        // 최대 1초치의 버퍼까지만 허용
        let threshold = ((maxBitrateKbps / 8) * 1000) * 1
        if writeBackPressure > threshold {
            logger.warning("High write backpressure (\(writeBackPressure) bytes), dropping frame")
            flushAll = true
            return (shouldDrop: true, needsKeyframe: false)
        }

        return (shouldDrop: false, needsKeyframe: false)
    }

    private func consumeKeyframeRequest() -> Bool {
        if needsKeyframeAfterPtsDrop {
            needsKeyframeAfterPtsDrop = false
            logger.debug("Requesting keyframe after PTS-based drops")
            return true
        }
        return false
    }
}
