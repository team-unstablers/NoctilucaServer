//
//  FrameDropController.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/28/26.
//

import Foundation
import CoreMedia

import SiriusKit

/// 프레임 드랍 정책을 관리하는 컨트롤러
/// PTS 기반 드랍과 backpressure 기반 드랍을 별도 메서드로 제공
class FrameDropController {
    private let logger = NoctilucaLogger(category: "FrameDropController")

    // MARK: - PTS 드랍 상태
    private var currentFrameRate: Float = 60.0
    private var consecutivePtsDropCount: Int = 0
    private var needsKeyframeAfterPtsDrop: Bool = false
    private let ptsDropKeyframeThreshold: Int = 3

    // MARK: - 프레임 레이트 제한
    private var maxFrameRate: Float? = nil   // nil = 제한 없음
    private var lastAcceptedPts: CMTime? = nil

    // MARK: - 큐 드랍 기반 플러시 상태
    private var consecutiveQueueDrops: Int = 0
    private let queueDropFlushThreshold: Int = 5
    private var flushCooldown: Int = 0
    private let flushCooldownFrames: Int = 10

    func configure(frameRate: Float) {
        self.currentFrameRate = frameRate
    }

    /// 최대 프레임 레이트를 설정합니다. nil이면 제한을 해제합니다.
    func configureMaxFrameRate(_ fps: Float?) {
        self.maxFrameRate = fps
        self.lastAcceptedPts = nil
    }

    /// PTS 기반 드랍 판정 (인코딩 전)
    /// - Returns: (shouldDrop: Bool, needsKeyframe: Bool)
    func shouldDropByPts(_ sampleBuffer: CMSampleBuffer) -> (shouldDrop: Bool, needsKeyframe: Bool) {
        let pts = sampleBuffer.presentationTimeStamp

        // Rate limiting: maxFrameRate 설정 시, 최소 간격 미만이면 드랍
        if let maxFps = maxFrameRate, let lastPts = lastAcceptedPts {
            let minInterval = 1.0 / Double(maxFps)
            let elapsed = pts.seconds - lastPts.seconds
            if elapsed >= 0 && elapsed < minInterval {
                return (shouldDrop: true, needsKeyframe: false)
            }
        }

        let systemNow = CMTime(value: Int64(mach_absolute_time()), timescale: 1_000_000_000)
        let latency = systemNow.seconds - pts.seconds

        // 음수 latency(미래 프레임)는 드랍하지 않음
        guard latency > 0 else {
            consecutivePtsDropCount = 0
            lastAcceptedPts = pts
            return (shouldDrop: false, needsKeyframe: consumeKeyframeRequest())
        }

        // frameRate 기반 동적 임계값: 2프레임분 지연 시 드랍
        let frameInterval = 1.0 / Double(max(currentFrameRate, 30))
        let threshold = frameInterval * 2.0

        if latency > threshold {
            consecutivePtsDropCount += 1
            logger.debug("Dropping frame due to PTS latency: \(latency)s (threshold: \(threshold)s, consecutive: \(self.consecutivePtsDropCount))")

            if consecutivePtsDropCount >= ptsDropKeyframeThreshold {
                needsKeyframeAfterPtsDrop = true
                consecutivePtsDropCount = 0
            }
            return (shouldDrop: true, needsKeyframe: false)
        }

        consecutivePtsDropCount = 0
        lastAcceptedPts = pts
        return (shouldDrop: false, needsKeyframe: consumeKeyframeRequest())
    }

    /// 큐 드랍 기반 플러시 판정 (인코딩 후)
    /// 연속 드랍이 임계치를 초과하면 큐 클리어 + 키프레임 요청
    func shouldFlushQueue(
        queueDropOccurred: Bool
    ) -> (shouldFlush: Bool, needsKeyframe: Bool) {
        if flushCooldown > 0 {
            flushCooldown -= 1
            consecutiveQueueDrops = 0
            return (shouldFlush: false, needsKeyframe: false)
        }

        if queueDropOccurred {
            consecutiveQueueDrops += 1
        } else {
            consecutiveQueueDrops = 0
        }

        if consecutiveQueueDrops >= queueDropFlushThreshold {
            logger.warning("Consecutive queue drops (\(self.consecutiveQueueDrops)), requesting flush + keyframe")
            consecutiveQueueDrops = 0
            flushCooldown = flushCooldownFrames
            return (shouldFlush: true, needsKeyframe: true)
        }

        return (shouldFlush: false, needsKeyframe: false)
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
