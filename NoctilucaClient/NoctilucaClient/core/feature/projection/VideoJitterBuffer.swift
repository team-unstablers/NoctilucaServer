//
//  VideoJitterBuffer.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 2/12/26.
//

import Foundation
import AVFoundation
import CoreMedia
import QuartzCore
import os

#if canImport(AppKit)
import AppKit
#endif

/// 디코딩된 비디오 프레임을 PTS 기반으로 버퍼링하고,
/// CADisplayLink를 통해 vsync에 동기화하여 일정한 간격으로 릴리즈하는 지터 버퍼.
///
/// AudioJitterBuffer와 동일한 앵커 기반 클록 동기화 및 3-state 머신 패턴을 사용한다.
final class VideoJitterBuffer: NSObject {

    // MARK: - Configuration

    struct Preset {
        let minBufferCount: Int
        let maxBufferCount: Int
        let lateThresholdMs: Double
        let lateResyncThresholdMs: Double
        let earlyResyncThresholdMs: Double
        let noReadyResyncConsecutiveTicks: Int
        
        /// 저지연 튜닝 전 기본값 프리셋.
        static let legacy = Preset(
            minBufferCount: 3,
            maxBufferCount: 4,
            lateThresholdMs: 50.0,
            lateResyncThresholdMs: 200.0,
            earlyResyncThresholdMs: 200.0,
            noReadyResyncConsecutiveTicks: 6
        )
        
        /// 현재 적용 중인 저지연 튜닝값 프리셋.
        static let lowLatency = Preset(
            minBufferCount: 2,
            maxBufferCount: 3,
            lateThresholdMs: 35.0,
            lateResyncThresholdMs: 150.0,
            earlyResyncThresholdMs: 120.0,
            noReadyResyncConsecutiveTicks: 4
        )
        
        /// 현재 저지연과 초저지연 사이의 중간 단계 프리셋.
        static let lowLatencyPlus = Preset(
            minBufferCount: 2,
            maxBufferCount: 2,
            lateThresholdMs: 28.0,
            lateResyncThresholdMs: 120.0,
            earlyResyncThresholdMs: 100.0,
            noReadyResyncConsecutiveTicks: 3
        )
        
        /// 지연 최소화를 최우선으로 하는 초저지연 프리셋.
        static let ultraLowLatency = Preset(
            minBufferCount: 1,
            maxBufferCount: 2,
            lateThresholdMs: 22.0,
            lateResyncThresholdMs: 90.0,
            earlyResyncThresholdMs: 80.0,
            noReadyResyncConsecutiveTicks: 2
        )
    }



    /// 현재 적용 중인 프리셋.
    let preset: Preset

    /// 재생을 시작하기 전 최소 버퍼 프레임 수.
    var minBufferCount: Int { preset.minBufferCount }

    /// 최대 버퍼 프레임 수 (초과 시 oldest drop).
    var maxBufferCount: Int { preset.maxBufferCount }

    /// Late threshold (ms). 이보다 늦은 프레임은 skip.
    var lateThresholdMs: Double { preset.lateThresholdMs }

    /// Hard lateness threshold (ms). 이보다 크게 늦으면 즉시 resync.
    var lateResyncThresholdMs: Double { preset.lateResyncThresholdMs }

    /// Hard earliness threshold (ms). 이보다 크게 빠른(미래) 프레임 상태가 지속되면 resync.
    var earlyResyncThresholdMs: Double { preset.earlyResyncThresholdMs }

    /// Ready 프레임이 없는 displayLink tick이 연속될 때, 이 횟수 이상이면 re-anchor를 시도.
    var noReadyResyncConsecutiveTicks: Int { preset.noReadyResyncConsecutiveTicks }

    // MARK: - State

    enum State {
        case buffering
        case playing
        case underflow
    }

    private(set) var state: State = .buffering

    // MARK: - Clock Synchronization

    /// 서버 PTS 앵커 (seconds).
    private var anchorRemotePTS: Double?

    /// 앵커 설정 시점의 로컬 호스트 시간 (mach_absolute_time).
    private var anchorHostTime: UInt64?

    /// mach_absolute_time → nanoseconds 변환 정보 (캐시).
    private let timebaseNumer: UInt64
    private let timebaseDenom: UInt64

    // MARK: - Buffer

    struct BufferedFrame {
        let pixelBuffer: CVPixelBuffer
        let remotePTS: Double // seconds
    }

    private var frameQueue: [BufferedFrame] = []

    // MARK: - Thread Safety

    private var lock = os_unfair_lock()

    // MARK: - Display Link

    private var displayLink: CADisplayLink?

    // MARK: - Output

    /// 프레임이 릴리즈 준비되었을 때 호출되는 콜백.
    /// CMSampleBuffer를 생성하여 전달한다.
    var onFrameReady: ((CMSampleBuffer) -> Void)?

    // MARK: - Statistics

    private var totalEnqueued: Int = 0
    private var totalDisplayed: Int = 0
    private var totalDropped: Int = 0
    private var totalLateSkipped: Int = 0

    // MARK: - Resync Tracking

    private var needsResyncAfterUnderflow: Bool = false
    private var consecutiveNoReadyTicks: Int = 0

    // MARK: - Logging

    private let logger = OSLog(subsystem: "app.noctiluca.client", category: "VideoJitterBuffer")

    // MARK: - Initialization

    init(preset: Preset = .lowLatency) {
        self.preset = preset

        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        self.timebaseNumer = UInt64(info.numer)
        self.timebaseDenom = UInt64(info.denom)

        super.init()

        frameQueue.reserveCapacity(maxBufferCount + 1)
    }

    deinit {
        displayLink?.invalidate()
    }

    // MARK: - Lifecycle

    /// CADisplayLink를 시작하여 프레임 릴리즈 루프를 가동한다.
    /// 반드시 메인 스레드에서 호출되거나, 내부적으로 메인 스레드로 디스패치된다.
    func start() {
        let link = createDisplayLink()
        link.add(to: .main, forMode: .common)
        displayLink = link

        os_log(.info, log: logger, "VideoJitterBuffer started (thread=%{public}@)", Thread.current.description)
    }

    private func createDisplayLink() -> CADisplayLink {
#if canImport(AppKit) && !targetEnvironment(macCatalyst)
        // macOS: CADisplayLink.init(target:selector:)가 불가하므로 NSScreen 팩토리 사용
        guard let screen = NSScreen.main else {
            fatalError("VideoJitterBuffer: NSScreen.main is unavailable")
        }
        return screen.displayLink(target: self, selector: #selector(displayLinkFired(_:)))
#else
        return CADisplayLink(target: self, selector: #selector(displayLinkFired(_:)))
#endif
    }

    /// CADisplayLink를 중단하고 버퍼를 비운다.
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        

        os_unfair_lock_lock(&lock)
        frameQueue.removeAll()
        os_unfair_lock_unlock(&lock)

        os_log(.info, log: logger,
               "VideoJitterBuffer stopped (enqueued=%d, displayed=%d, dropped=%d, lateSkipped=%d)",
               totalEnqueued, totalDisplayed, totalDropped, totalLateSkipped)
    }

    /// 버퍼를 리셋한다 (앵커, 상태, 큐 모두 초기화).
    func reset() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        frameQueue.removeAll()
        state = .buffering
        anchorRemotePTS = nil
        anchorHostTime = nil
        needsResyncAfterUnderflow = false
        consecutiveNoReadyTicks = 0

        os_log(.info, log: logger, "VideoJitterBuffer reset")
    }

    // MARK: - Enqueue (Producer - decoder thread)

    /// 디코딩된 프레임을 버퍼에 추가한다.
    /// - Parameters:
    ///   - pixelBuffer: 디코딩된 CVPixelBuffer
    ///   - remotePTS: 서버 PTS (seconds)
    func enqueue(pixelBuffer: CVPixelBuffer, remotePTS: Double) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        // 앵커 설정 (첫 프레임)
        if anchorRemotePTS == nil {
            setAnchorLocked(remotePTS: remotePTS)
        }

        // Underflow 후: 버퍼를 비우지 않고 앵커만 재설정한다.
        // 이미 쌓인 프레임을 보존하여 불필요한 재버퍼링을 방지한다.
        if needsResyncAfterUnderflow {
            needsResyncAfterUnderflow = false
            state = .buffering
            consecutiveNoReadyTicks = 0
            setAnchorLocked(remotePTS: frameQueue.first?.remotePTS ?? remotePTS)
        }

        // Late 프레임 체크 (playing 상태에서만)
        if state == .playing {
            let lateness = latenessLocked(of: remotePTS)
            let lateThreshold = lateThresholdMs / 1000.0
            let resyncThreshold = lateResyncThresholdMs / 1000.0
            let earlyResyncThreshold = earlyResyncThresholdMs / 1000.0

            if lateness > resyncThreshold {
                os_log(.info, log: logger,
                       "Resyncing: frame late by %.1f ms (threshold %.1f ms)",
                       lateness * 1000, resyncThreshold * 1000)
                resyncLocked(remotePTS: remotePTS, reason: "lateness")
            } else if lateness < -earlyResyncThreshold {
                // 기준점이 과거에 묶여 프레임이 계속 "미래"로 판정되는 starvation 상태를 복구한다.
                os_log(.info, log: logger,
                       "Resyncing: frame early by %.1f ms (threshold %.1f ms)",
                       -lateness * 1000, earlyResyncThreshold * 1000)
                resyncLocked(remotePTS: remotePTS, reason: "earliness")
            } else if lateness > lateThreshold {
                totalLateSkipped += 1
                os_log(.debug, log: logger,
                       "Skipping late frame: %.1f ms late",
                       lateness * 1000)
                return
            }
        }

        // 프레임 삽입 (PTS 순서 유지)
        let frame = BufferedFrame(pixelBuffer: pixelBuffer, remotePTS: remotePTS)
        insertSortedLocked(frame)
        totalEnqueued += 1

        // 버퍼 오버플로 처리:
        // - 일반 상황: oldest drop (지연 누적 방지)
        // - ready 프레임이 하나도 없는 starvation 상황: newest drop (표시 가능한 쪽 보존)
        if frameQueue.count > maxBufferCount {
            if isStarvingLocked() {
                frameQueue.removeLast()
                totalDropped += 1
                os_log(.debug, log: logger, "Buffer overflow during starvation, dropped newest frame")
            } else {
                frameQueue.removeFirst()
                totalDropped += 1
                os_log(.debug, log: logger, "Buffer overflow, dropped oldest frame")
            }
        }

        // 상태 전환 체크
        switch state {
        case .buffering:
            if frameQueue.count >= minBufferCount {
                state = .playing
                // 앵커를 재설정하여 가장 오래된 버퍼 프레임이 "지금"부터 릴리즈되도록 한다.
                // 이렇게 하지 않으면 버퍼링 동안 축적된 프레임이 모두 "과거"로 판정되어
                // displayLink 한 틱에 전부 소비되고 즉시 underflow가 발생한다.
                if let oldest = frameQueue.first {
                    setAnchorLocked(remotePTS: oldest.remotePTS)
                }
                os_log(.info, log: logger,
                       "Buffering complete, starting playback (%d frames buffered)",
                       frameQueue.count)
            }
        case .underflow:
            if frameQueue.count >= minBufferCount {
                state = .playing
                if let oldest = frameQueue.first {
                    setAnchorLocked(remotePTS: oldest.remotePTS)
                }
                os_log(.info, log: logger,
                       "Recovered from underflow (%d frames buffered)",
                       frameQueue.count)
            }
        case .playing:
            break
        }
    }

    // MARK: - Dequeue (Consumer - CADisplayLink / main thread)

    @objc private func displayLinkFired(_ link: CADisplayLink) {
        os_unfair_lock_lock(&lock)

        guard state == .playing, !frameQueue.isEmpty else {
            os_unfair_lock_unlock(&lock)
            return
        }

        let currentTime = elapsedSecondsFromAnchorLocked()
        guard let currentTime else {
            os_unfair_lock_unlock(&lock)
            return
        }

        // ready 프레임 찾기: remotePTS(앵커 기준 상대) <= currentTime
        var lastReadyIndex: Int? = nil
        for i in 0..<frameQueue.count {
            let relativePTS = frameQueue[i].remotePTS - (anchorRemotePTS ?? 0)
            if relativePTS <= currentTime {
                lastReadyIndex = i
            } else {
                break // PTS 순서로 정렬되어 있으므로 이후는 모두 미래
            }
        }

        guard let readyIdx = lastReadyIndex else {
            consecutiveNoReadyTicks += 1

            if consecutiveNoReadyTicks >= noReadyResyncConsecutiveTicks,
               frameQueue.count >= minBufferCount,
               let oldest = frameQueue.first {
                // ready 프레임이 연속으로 없으면 앵커를 oldest 기준으로 재설정해 starvation을 해소한다.
                setAnchorLocked(remotePTS: oldest.remotePTS)
                consecutiveNoReadyTicks = 0
                os_log(.info, log: logger, "Resynced due to no-ready starvation")
            }

            os_unfair_lock_unlock(&lock)
            return
        }

        consecutiveNoReadyTicks = 0

        // 가장 최신 ready 프레임만 표시 (이전 것들은 skip)
        let frameToDisplay = frameQueue[readyIdx]
        let skipped = readyIdx // 0부터 readyIdx-1까지가 skip된 프레임
        totalDropped += skipped
        totalDisplayed += 1

        // ready 프레임까지 제거
        frameQueue.removeFirst(readyIdx + 1)

        // underflow 체크
        if frameQueue.isEmpty {
            state = .underflow
            needsResyncAfterUnderflow = true
            consecutiveNoReadyTicks = 0
            os_log(.debug, log: logger, "Underflow: buffer exhausted after display")
        }

        os_unfair_lock_unlock(&lock)

        // Lock 밖에서 CMSampleBuffer 생성 및 콜백 호출
        if let sampleBuffer = makeSampleBuffer(from: frameToDisplay) {
            onFrameReady?(sampleBuffer)
        }
    }

    // MARK: - Private: Clock

    private func setAnchorLocked(remotePTS: Double) {
        anchorRemotePTS = remotePTS
        anchorHostTime = mach_absolute_time()
        os_log(.debug, log: logger, "Anchor set: remotePTS=%.3f", remotePTS)
    }

    private func resyncLocked(remotePTS: Double, reason: String) {
        frameQueue.removeAll()
        state = .buffering
        needsResyncAfterUnderflow = false
        consecutiveNoReadyTicks = 0
        setAnchorLocked(remotePTS: remotePTS)
        os_log(.info, log: logger, "Resynced (%{public}s)", reason)
    }

    /// 앵커 시점으로부터 경과한 시간 (seconds).
    private func elapsedSecondsFromAnchorLocked() -> Double? {
        guard let anchorHost = anchorHostTime else { return nil }
        let now = mach_absolute_time()
        let elapsedTicks = now - anchorHost
        let elapsedNanos = elapsedTicks * timebaseNumer / timebaseDenom
        return Double(elapsedNanos) / 1_000_000_000.0
    }

    /// 프레임의 lateness를 계산한다 (양수 = 늦음).
    private func latenessLocked(of remotePTS: Double) -> Double {
        guard let anchorPTS = anchorRemotePTS,
              let elapsed = elapsedSecondsFromAnchorLocked() else {
            return 0
        }
        let expectedPTS = anchorPTS + elapsed
        return expectedPTS - remotePTS
    }

    // MARK: - Private: Buffer Management

    /// PTS 순서를 유지하며 프레임을 삽입한다.
    private func insertSortedLocked(_ frame: BufferedFrame) {
        // 대부분의 경우 새 프레임이 가장 뒤에 오므로 역순 탐색
        var insertIndex = frameQueue.count
        while insertIndex > 0 && frameQueue[insertIndex - 1].remotePTS > frame.remotePTS {
            insertIndex -= 1
        }
        frameQueue.insert(frame, at: insertIndex)
    }

    /// 현재 시점에서 ready 프레임이 하나도 없는 미래-치우침 상태인지 여부.
    private func isStarvingLocked() -> Bool {
        guard let anchorPTS = anchorRemotePTS,
              let elapsed = elapsedSecondsFromAnchorLocked(),
              let oldest = frameQueue.first else {
            return false
        }
        let oldestRelativePTS = oldest.remotePTS - anchorPTS
        return oldestRelativePTS > elapsed
    }

    // MARK: - Private: CMSampleBuffer Creation

    private func makeSampleBuffer(from frame: BufferedFrame) -> CMSampleBuffer? {
        let now = mach_absolute_time()
        let presentationTime = CMTimeMake(value: Int64(now), timescale: 1_000_000_000)

        do {
            let sampleBuffer = try CMSampleBuffer(
                imageBuffer: frame.pixelBuffer,
                formatDescription: CMFormatDescription(imageBuffer: frame.pixelBuffer),
                sampleTiming: CMSampleTimingInfo(
                    duration: CMTime.invalid,
                    presentationTimeStamp: presentationTime,
                    decodeTimeStamp: CMTime.invalid
                )
            )
            return sampleBuffer
        } catch {
            os_log(.error, log: logger, "Failed to create CMSampleBuffer: %{public}@", error.localizedDescription)
            return nil
        }
    }
}
