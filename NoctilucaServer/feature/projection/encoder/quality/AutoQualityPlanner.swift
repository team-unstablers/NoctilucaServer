//
//  QualityPlanner.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/18/25.
//

import Foundation
import SiriusKit
import CoreGraphics

struct AutoQualityPreset {
    let targetBitrateKbps: Int
    let maxBitrateKbps: Int
}


extension AutoQualityPreset {
    static func preset(for codec: CodecFourCC, resolution: CGSize, frameRate: Float) -> AutoQualityPreset {
        switch codec {
        case .avc1: // H.264
            return h264Preset(resolution: resolution, frameRate: frameRate)
        case .hvc1: // H.265 (HEVC)
            return hevcPreset(resolution: resolution, frameRate: frameRate)
        default:
            return h264Preset(resolution: resolution, frameRate: frameRate)
        }
    }
    
    // FPS 스케일링 로직 유지 (60fps 기준)
    private static func calculateFpsScale(_ fps: Float) -> Double {
        /*
        let baseFps: Double = 60.0
        let currentFps = Double(max(30, fps))
        return currentFps / baseFps
         */
        
        return 1
    }
    
    static func h264Preset(resolution: CGSize, frameRate: Float) -> AutoQualityPreset {
        let pixelCount = Int(resolution.width * resolution.height)
        let scale = calculateFpsScale(frameRate)
        
        // [전략] 내부 알고리즘이 1.5배 뻥튀기할 것을 고려하여
        // Target은 '화질이 안 깨지는 마지노선', Max는 '부스트 전의 안전 상한선'으로 설정
        
        let target: Double
        let maxRate: Double
        
        switch pixelCount {
        case 0..<CodecResolutionLevel.sd480p.pixelCount:
            // ~480p
            target = 500   // 1.5배시 750k
            maxRate = 1_000
            
        case CodecResolutionLevel.sd480p.pixelCount..<CodecResolutionLevel.hd720p.pixelCount:
            // 480p ~ 720p
            target = 1_500 // 1.5배시 2.25M
            maxRate = 3_000
            
        case CodecResolutionLevel.hd720p.pixelCount..<CodecResolutionLevel.hd1080p.pixelCount:
            // 720p ~ 1080p (핵심 구간)
            // H.264 1080p는 4Mbps 밑으로 가면 텍스트 주변에 노이즈(Artifact)가 생기기 시작함.
            // 따라서 4,000을 바닥으로 잡음.
            target = 4_000 // 1.5배시 6M (상당히 준수함)
            maxRate = 8_000
            
        case CodecResolutionLevel.hd1080p.pixelCount..<CodecResolutionLevel.hd2k.pixelCount:
            // 1080p ~ 2K
            target = 8_000 // 1.5배시 12M
            maxRate = 14_000
            
        case CodecResolutionLevel.hd2k.pixelCount..<CodecResolutionLevel.hd4k.pixelCount:
            // 2K ~ 4K
            target = 12_000 // 1.5배시 18M
            maxRate = 20_000
            
        default:
            // 4K 이상
            target = 18_000 // 1.5배시 27M
            maxRate = 30_000
        }
        
        return AutoQualityPreset(
            targetBitrateKbps: Int(target * scale),
            maxBitrateKbps: Int(maxRate * scale)
        )
    }
    
    static func hevcPreset(resolution: CGSize, frameRate: Float) -> AutoQualityPreset {
        let pixelCount = Int(resolution.width * resolution.height)
        let scale = calculateFpsScale(frameRate)
        
        // H.265는 압축률이 좋아 더 과감하게 낮출 수 있음
        
        let target: Double
        let maxRate: Double
        
        switch pixelCount {
        case 0..<CodecResolutionLevel.sd480p.pixelCount:
            target = 300    // 1.5배시 450k
            maxRate = 600
            
        case CodecResolutionLevel.sd480p.pixelCount..<CodecResolutionLevel.hd720p.pixelCount:
            target = 800    // 1.5배시 1.2M
            maxRate = 1_500
            
        case CodecResolutionLevel.hd720p.pixelCount..<CodecResolutionLevel.hd1080p.pixelCount:
            // 1080p HEVC
            // 2.5Mbps면 사무용으로는 차고 넘치며, 영상 볼 때 1.5배(3.75M) 되면 충분함
            target = 2_500  // 1.5배시 3.75M
            maxRate = 5_000
            
        case CodecResolutionLevel.hd1080p.pixelCount..<CodecResolutionLevel.hd2k.pixelCount:
            // 2K
            target = 5_000  // 1.5배시 7.5M
            maxRate = 9_000
            
        case CodecResolutionLevel.hd2k.pixelCount..<CodecResolutionLevel.hd4k.pixelCount:
            // 4K
            // 4K HEVC 10M는 넷플릭스 4K 권장 사양의 절반 수준이지만,
            // 정적인 화면(코딩, 웹서핑)에서는 매우 선명함.
            target = 10_000 // 1.5배시 15M
            maxRate = 18_000
            
        default:
            // 4K 이상
            target = 15_000 // 1.5배시 22.5M
            maxRate = 28_000
        }
        
        return AutoQualityPreset(
            targetBitrateKbps: Int(target * scale),
            maxBitrateKbps: Int(maxRate * scale)
        )
    }
}


private enum AutoQualityState {
    case initial
    case stable
    case adjustingUp
    case adjustingDown
}

enum AutoQualityStrategy {
    /// A balanced approach between quality and performance.
    case balanced
    
    /// Prioritizes video quality over performance.
    case qualityFirst
    
    /// Prioritizes performance over video quality.
    case performanceFirst
}

struct QualityAdjustmentEvent {
    enum Direction {
        case degraded
        case recovered
    }

    enum Trigger {
        case clientFeedback
        case networkThroughput
        case both
    }

    let direction: Direction
    let trigger: Trigger
    let isCritical: Bool
    let degradationIndex: Int
}

class AutoQualityPlanner: QualityPlanner {
    var allowDegradation: Bool = true

    let codec: CodecFourCC
    let resolution: CGSize
    let frameRate: Float

    let preset: AutoQualityPreset
    var strategy: AutoQualityStrategy

    var onQualityAdjustment: ((QualityAdjustmentEvent) -> Void)?

    private var state: AutoQualityState
    private var multiplier: Float = 1.0
    private(set) var degradationIndex: Int = 0
    private var degradationSteps: [QualityDegradation]
    
    // EMA state
    private var emaDropRatio: Float?
    private var emaDecodeMs: Float?
    private var emaBackpressure: Float?

    // scoring / pacing (피드 소스 분리)
    private var clientScore: Int = 0   // feed(report:)에서 증감
    private var serverScore: Int = 0   // feed(queuePressure:)에서 증감
    private var cooldownTicks: Int = 0
    private let cooldownWindow: Int = 3

    // thresholds
    private let dropThreshold: Float = 0.05
    private let dropCriticalThreshold: Float = 0.15
    private let recoveryDropThreshold: Float = 0.01
    private let decodeBudgetSlack: Float = 0.7

    // 긴급 디그레이드 threshold
    private let emergencyDropThreshold: Float = 0.30    // 드랍 30% 이상
    private let emergencyPressureThreshold: Float = 0.9 // 큐 90% 이상 가득 참

    // EMA smoothing (~3 ticks window)
    private let emaAlpha: Float = 0.5
    private let backpressureThreshold: Float = 0.5

    private let minMultiplier: Float = 0.4
    private let maxMultiplier: Float = 1.5
    
    required init(codec: CodecFourCC, resolution: CGSize, frameRate: Float) {
        self.codec = codec
        self.resolution = resolution
        self.frameRate = frameRate
        
        self.strategy = .balanced
        self.preset = AutoQualityPreset.preset(for: codec, resolution: resolution, frameRate: frameRate)
        self.degradationSteps = AutoQualityPlanner.makeDegradationSteps(for: .balanced, codec: codec, resolution: resolution, frameRate: frameRate)

        self.state = .initial
    }

    convenience init(codec: CodecFourCC, resolution: CGSize, frameRate: Float, strategy: AutoQualityStrategy) {
        self.init(codec: codec, resolution: resolution, frameRate: frameRate)
        self.strategy = strategy
        self.degradationSteps = AutoQualityPlanner.makeDegradationSteps(for: strategy, codec: codec, resolution: resolution, frameRate: frameRate)
    }
    
    func feed(report: ProjectionPerformanceReport) {
        let received = Int(report.receivedFrameCount)
        let dropped = Int(report.droppedFrameCount)
        let decodeMsRaw = Float(report.averageDecodeTimeMs)

        guard received > 0 else {
            // No traffic: slowly encourage recovery
            clientScore -= 1
            maybeAdjustPlan()
            return
        }

        let dropRatio = Float(dropped) / Float(received)

        // 긴급 경로: raw 값이 극단적이면 즉시 디그레이드
        if dropRatio >= emergencyDropThreshold && cooldownTicks == 0 {
            applyDegradation(critical: true, trigger: .clientFeedback)
            emaDropRatio = nil
            emaDecodeMs = nil
            return
        }

        // EMA smoothing over ~3 ticks
        emaDropRatio = smooth(emaDropRatio, with: dropRatio)
        emaDecodeMs = smooth(emaDecodeMs, with: decodeMsRaw)

        let smoothedDrop = emaDropRatio ?? dropRatio
        let smoothedDecode = emaDecodeMs ?? decodeMsRaw

        let frameBudgetMs: Float = {
            let fps = max(frameRate, 1)
            return (1000.0 / fps) * decodeBudgetSlack
        }()
        let decodeOverBudget = smoothedDecode > frameBudgetMs

        if smoothedDrop >= dropCriticalThreshold {
            clientScore += 2
        } else if smoothedDrop >= dropThreshold {
            clientScore += 1
        }

        if decodeOverBudget {
            clientScore += 1
        }

        if smoothedDrop < recoveryDropThreshold && decodeOverBudget == false {
            clientScore -= 1
        }

        maybeAdjustPlan()
    }
    
    func feed(queuePressure: Float) {
        let clamped = min(max(queuePressure, 0.0), 1.0)

        // 긴급 경로: 큐가 거의 가득 차면 즉시 디그레이드
        if clamped >= emergencyPressureThreshold && cooldownTicks == 0 {
            applyDegradation(critical: true, trigger: .networkThroughput)
            emaBackpressure = nil
            return
        }

        emaBackpressure = smooth(emaBackpressure, with: clamped)
        let smoothed = emaBackpressure ?? clamped

        if smoothed >= backpressureThreshold {
            serverScore += 2
        } else {
            serverScore -= 1
        }
        maybeAdjustPlan()
    }
    
    func targetBitrateKbps() -> Int {
        let adjusted = Float(preset.targetBitrateKbps) * multiplier
        return max(1, Int(adjusted))
    }
    
    func maxBitrateKbps() -> Int {
        let adjusted = Float(preset.maxBitrateKbps) * multiplier
        return max(1, Int(adjusted))
    }
    
    func plannedDegradations() -> [QualityDegradation] {
        guard allowDegradation else { return [] }
        guard degradationSteps.isEmpty == false else { return [] }
        
        let end = min(degradationIndex, degradationSteps.count)
        return Array(degradationSteps.prefix(end))
    }
}

private extension AutoQualityPlanner {
    static func makeDegradationSteps(
        for strategy: AutoQualityStrategy,
        codec: CodecFourCC,
        resolution: CGSize,
        frameRate: Float
    ) -> [QualityDegradation] {
        let fps90 = max(frameRate * 0.9, 1)
        let fps75 = max(frameRate * 0.75, 1)

        let q85 = QualityDegradation.lowerQuality(factor: 0.85)
        let q70 = QualityDegradation.lowerQuality(factor: 0.70)

        let res85 = QualityDegradation.lowerResolution(scale: 0.85)
        let res70 = QualityDegradation.lowerResolution(scale: 0.7)
        let res50 = QualityDegradation.lowerResolution(scale: 0.5)

        let fps90d = QualityDegradation.lowerFrameRate(to: fps90)
        let fps75d = QualityDegradation.lowerFrameRate(to: fps75)

        let quant1 = QualityDegradation.increaseQuantization(level: 1)
        let quant2 = QualityDegradation.increaseQuantization(level: 2)
        let quant3 = QualityDegradation.increaseQuantization(level: 3)

        let isImageCodec = (codec == .mjpg || codec == .webp || codec == .zrle)

        if isImageCodec {
            switch strategy {
            case .balanced:
                return [quant1, q85, res85, fps90d, quant2, q70, res70, fps75d, quant3]
            case .performanceFirst:
                return [quant1, q85, quant2, res85, q70, quant3, res70, res50, fps90d, fps75d]
            case .qualityFirst:
                return [fps90d, fps75d, quant1, q85, res85, quant2, q70, res70]
            }
        } else {
            // VT 코덱 (H.264/H.265) — 기존 유지
            switch strategy {
            case .balanced:
                return [q85, res85, fps90d, q70, res70, fps75d]
            case .performanceFirst:
                return [q85, res85, q70, res70, res50, fps90d, fps75d]
            case .qualityFirst:
                return [fps90d, fps75d, q85, res85, q70, res70]
            }
        }
    }
    
    func clampMultiplier(_ value: Float) -> Float {
        return min(max(value, minMultiplier), maxMultiplier)
    }
    
    func applyDegradation(critical: Bool, trigger: QualityAdjustmentEvent.Trigger) {
        state = .adjustingDown
        let step = critical ? 2 : 1
        degradationIndex = min(degradationIndex + step, degradationSteps.count)

        let factor: Float = critical ? 0.65 : 0.8
        multiplier = clampMultiplier(multiplier * factor)
        cooldownTicks = cooldownWindow

        let event = QualityAdjustmentEvent(
            direction: .degraded,
            trigger: trigger,
            isCritical: critical,
            degradationIndex: degradationIndex
        )
        onQualityAdjustment?(event)

        clientScore = 0
        serverScore = 0
    }

    func applyRecovery() {
        state = .adjustingUp
        if degradationIndex > 0 {
            degradationIndex -= 1
        }

        multiplier = clampMultiplier(multiplier * 1.05)
        cooldownTicks = cooldownWindow

        let event = QualityAdjustmentEvent(
            direction: .recovered,
            trigger: .both,
            isCritical: false,
            degradationIndex: degradationIndex
        )
        onQualityAdjustment?(event)

        clientScore = 0
        serverScore = 0

        if degradationIndex == 0 {
            state = .stable
        }
    }

    func smooth(_ current: Float?, with newValue: Float) -> Float {
        guard let current else { return newValue }
        return (emaAlpha * newValue) + ((1 - emaAlpha) * current)
    }

    func maybeAdjustPlan() {
        if cooldownTicks > 0 {
            cooldownTicks -= 1
            return
        }

        // 둘 중 하나라도 threshold 초과 시 디그레이드
        let maxScore = max(clientScore, serverScore)
        if maxScore >= 3 {
            let trigger: QualityAdjustmentEvent.Trigger
            if clientScore >= 3 && serverScore >= 3 {
                trigger = .both
            } else if clientScore >= serverScore {
                trigger = .clientFeedback
            } else {
                trigger = .networkThroughput
            }
            applyDegradation(critical: maxScore >= 4, trigger: trigger)
            return
        }

        // 회복은 양쪽 모두 안정적이어야 함
        if clientScore <= -3 && serverScore <= -3 {
            applyRecovery()
            return
        }
    }
}
