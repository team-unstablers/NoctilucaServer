//
//  AudioProjectionSession.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/28/26.
//

import Foundation
import os
import AVFoundation
import CoreMedia
import Accelerate
import Atomics

import SiriusKitClient

enum AudioProjectionSessionEvent: Sendable {
    /// 오류가 발생했습니다.
    case errorOccurred(Error, fatal: Bool)
}

/// Audio projection session that handles audio decoding and playback.
///
/// Uses `AVAudioSourceNode` (pull-based) with a jitter buffer for accurate
/// PTS-based timing and smooth playback.
///
/// ## 동시성 모델 (hybrid 격리)
///
/// - **Actor-isolated**: `decoder`, `sourceNode`, `outputFormat`, `codec`, 라이프사이클 상태.
/// - **nonisolated (render callback 경로)**: `jitterBuffer` (내부 lock 으로 thread-safe),
///   `isStartedFlag`, `isStoppingFlag`, `fadeOutCompleteFlag` (ManagedAtomic),
///   `fadeGainLock` (OSAllocatedUnfairLock).
///
/// audio render callback 은 CoreAudio 의 real-time thread 에서 호출되므로 actor executor
/// 로 잡을 수 없다. 따라서 render callback 이 건드리는 필드만 분리해 lock-free 또는
/// real-time-safe unfair lock 으로 보호한다
actor AudioProjectionSession: Identifiable {
    private let logger = SiriusLogger(category: "AudioProjectionSession", subsystem: "app.noctiluca.client")

    // MARK: - Immutable (nonisolated let)

    nonisolated let id: UUID
    nonisolated let dataChannel: ProjectionDataChannel

    // Rule I 패턴 3: init 에서 1회 대입 후 read-only.
    nonisolated(unsafe) weak var controlChannel: ProjectionChannel?

    nonisolated let audioJitterBufferPreset: AudioJitterBuffer.Preset

    /// init 에서 1회 생성. 내부 lock 으로 thread-safe (Rule G 예외).
    nonisolated let jitterBuffer: AudioJitterBuffer

    /// 외부 노출 이벤트 스트림
    nonisolated let events: AsyncStream<AudioProjectionSessionEvent>
    nonisolated private let continuation: AsyncStream<AudioProjectionSessionEvent>.Continuation

    // MARK: - Debug snapshot (nonisolated read)

    struct DebugSnapshot: Sendable {
        let codec: SiriusKitClient.AudioCodec?
    }

    nonisolated private let debugSnapshotLock = OSAllocatedUnfairLock<DebugSnapshot>(
        initialState: DebugSnapshot(codec: nil)
    )

    nonisolated var debugSnapshot: DebugSnapshot {
        debugSnapshotLock.withLock { $0 }
    }

    private func updateDebugSnapshot() {
        let snapshot = DebugSnapshot(codec: self.codec)
        debugSnapshotLock.withLock { $0 = snapshot }
    }

    // MARK: - Render callback state (nonisolated, real-time safe)

    nonisolated let isStartedFlag = ManagedAtomic<Bool>(false)
    nonisolated let isStoppingFlag = ManagedAtomic<Bool>(false)
    nonisolated let fadeOutCompleteFlag = ManagedAtomic<Bool>(false)

    /// Current fade gain (0.0 = silent, 1.0 = full volume).
    /// render callback 과 라이프사이클 메서드 양쪽에서 접근하므로 lock 으로 보호.
    nonisolated let fadeGainLock = OSAllocatedUnfairLock<Float>(initialState: 1.0)

    /// Fade step per sample for smooth transitions. 10ms @ 48kHz.
    nonisolated let fadeStepPerSample: Float = 1.0 / 480.0

    // MARK: - Actor-isolated mutable state

    private(set) var decoder: (any AudioDecoder)?
    private(set) var codec: SiriusKitClient.AudioCodec?

    private var sourceNode: AVAudioSourceNode?

    /// Output format for the audio engine (48kHz, stereo, Float32)
    private var outputFormat: AVAudioFormat?

    private var dataChannelConsumerTask: Task<Void, Never>?

    // MARK: - Init

    init(
        id: UUID,
        dataChannel: ProjectionDataChannel,
        controlChannel: ProjectionChannel,
        audioJitterBufferPreset: AudioJitterBuffer.Preset = .latencyFirst
    ) {
        self.id = id
        self.dataChannel = dataChannel
        self.controlChannel = controlChannel
        self.audioJitterBufferPreset = audioJitterBufferPreset

        self.jitterBuffer = AudioJitterBuffer(
            sampleRate: 48000,
            maxDurationMs: 500,
            preset: audioJitterBufferPreset
        )

        var continuationLocal: AsyncStream<AudioProjectionSessionEvent>.Continuation!
        self.events = AsyncStream<AudioProjectionSessionEvent>(
            AudioProjectionSessionEvent.self,
            bufferingPolicy: .unbounded
        ) { continuation in
            continuationLocal = continuation
        }
        self.continuation = continuationLocal
    }

    /// Consume dataChannel events 시작 및 기타 비동기 초기화.
    func setup() async {
        dataChannelConsumerTask = Task { [weak self] in
            await self?.consumeDataChannelEvents()
        }
    }

    deinit {
        continuation.finish()
    }

    // MARK: - Data channel consumer

    private func consumeDataChannelEvents() async {
        for await event in dataChannel.events {
            switch event {
            case .audioFrame(let frame):
                handleEncodedFrame(frame)

            case .videoFrame, .codecParameterSets, .degradationNotice:
                // 비디오 세션이 처리
                break

            case .closed, .error:
                return
            }
        }
    }

    /// Handles an encoded audio frame from the data channel.
    private func handleEncodedFrame(_ frame: EncodedAudioFrameInput) {
        guard isStartedFlag.load(ordering: .acquiring) else { return }

        do {
            try decoder?.decode(frame)
        } catch {
            logger.error("Failed to decode audio frame: \(error.localizedDescription)")
        }
    }

    // MARK: - Lifecycle

    /// Prepares the session with the given codec.
    func prepare(codec: SiriusKitClient.AudioCodec) async throws {
        self.codec = codec

        // Clean up existing decoder
        try? decoder?.stop()
        decoder = nil

        // Select decoder based on codec
        let selectedDecoder: any AudioDecoder
        switch codec.fourCC {
        case .pcmu, .pcma:
            selectedDecoder = PCMAudioDecoder()
        case .opus:
            selectedDecoder = OpusAudioDecoder()
        default:
            throw AudioDecoderError.unsupportedCodec(codec.fourCC.stringRepresentation)
        }

        selectedDecoder.delegate = self
        self.decoder = selectedDecoder

        // Configure decoder
        let configuration = AudioDecoderConfiguration(
            codec: codec,
            outputSampleRate: 48000,
            outputChannelCount: 2
        )
        try selectedDecoder.prepare(with: configuration)

        // Setup source node
        try setupSourceNode()

        updateDebugSnapshot()
        logger.info("AudioProjectionSession prepared with codec: \(codec.fourCC.stringRepresentation)")
    }

    /// Starts audio decoding and playback.
    func start() async throws {
        guard let decoder = decoder else {
            throw AudioDecoderError.notPrepared
        }
        guard let sourceNode = sourceNode, let outputFormat = outputFormat else {
            throw AudioDecoderError.notPrepared
        }

        // Reset jitter buffer and fade state
        jitterBuffer.reset()
        fadeGainLock.withLock { $0 = 1.0 }
        isStoppingFlag.store(false, ordering: .releasing)
        fadeOutCompleteFlag.store(false, ordering: .releasing)

        try decoder.start()

        do {
            // Attach to shared engine
            try await NOCAudioEngine.shared.attach(sourceNode, format: outputFormat)
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
            throw error
        }

        isStartedFlag.store(true, ordering: .releasing)

        logger.info("AudioProjectionSession started (jitter buffer mode)")
    }

    /// Stops audio decoding and playback.
    func stop() async throws {
        let wasStarted = isStartedFlag.exchange(false, ordering: .acquiringAndReleasing)
        let wasStopping = isStoppingFlag.load(ordering: .acquiring)
        guard wasStarted || wasStopping else { return }

        if sourceNode != nil {
            // render callback 에서 fade-out 을 수행하도록 신호.
            // jitter buffer 는 아직 reset 하지 않음 — render callback 이 남은 데이터를
            // fade-out 에 사용한다.
            isStoppingFlag.store(true, ordering: .releasing)
            fadeOutCompleteFlag.store(false, ordering: .releasing)

            // render callback 이 fade-out 을 완료할 때까지 최대 ~30ms 대기.
            // fade-out 은 ~10ms (480 samples @ 48kHz).
            for _ in 0..<30 {
                if fadeOutCompleteFlag.load(ordering: .acquiring) { break }
                try? await Task.sleep(nanoseconds: 1_000_000)  // 1ms
            }

            isStoppingFlag.store(false, ordering: .releasing)
        }

        if let sourceNode = sourceNode {
            NOCAudioEngine.shared.detach(sourceNode)
        }

        try decoder?.stop()
        decoder = nil

        jitterBuffer.reset()

        dataChannelConsumerTask?.cancel()
        dataChannelConsumerTask = nil

        logger.info("AudioProjectionSession stopped")
    }

    // MARK: - Audio Engine Setup

    private func setupSourceNode() throws {
        // Create output format (48kHz, stereo, Float32, NON-INTERLEAVED)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) else {
            throw AudioDecoderError.unsupportedFormat
        }
        self.outputFormat = format

        // Create AVAudioSourceNode (pull-based)
        let sourceNode = AVAudioSourceNode(format: format) { [weak self] silence, timestamp, frameCount, audioBufferList in
            guard let self = self else {
                silence.pointee = true
                return noErr
            }
            return self.renderCallback(
                silence: silence,
                timestamp: timestamp,
                frameCount: frameCount,
                audioBufferList: audioBufferList
            )
        }

        self.sourceNode = sourceNode

        logger.info("Audio source node setup complete")
    }

    // MARK: - Render Callback (nonisolated, real-time safe)

    /// Audio render callback. Called from the real-time audio thread.
    /// - Warning: This runs on a real-time thread. Avoid memory allocation, locks, and Objective-C dispatch.
    nonisolated private func renderCallback(
        silence: UnsafeMutablePointer<ObjCBool>,
        timestamp: UnsafePointer<AudioTimeStamp>,
        frameCount: AVAudioFrameCount,
        audioBufferList: UnsafeMutablePointer<AudioBufferList>
    ) -> OSStatus {
        let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let requestedFrames = Int(frameCount)

        // For non-interleaved stereo, we have 2 separate buffers (L and R)
        guard bufferList.count >= 2,
              let leftBuffer = bufferList[0].mData?.assumingMemoryBound(to: Float.self),
              let rightBuffer = bufferList[1].mData?.assumingMemoryBound(to: Float.self) else {
            silence.pointee = true
            return noErr
        }

        // stop() 호출 시: 남은 데이터를 fade-out 하며 재생
        if isStoppingFlag.load(ordering: .acquiring) {
            let currentGain = fadeGainLock.withLock { $0 }
            if currentGain > 0 {
                _ = jitterBuffer.dequeue(intoLeft: leftBuffer, intoRight: rightBuffer, frameCount: requestedFrames)
                applyFadeOutNonInterleaved(left: leftBuffer, right: rightBuffer, frameCount: requestedFrames)
                silence.pointee = false
            } else {
                fillSilenceNonInterleaved(left: leftBuffer, right: rightBuffer, frameCount: requestedFrames)
                silence.pointee = true
                fadeOutCompleteFlag.store(true, ordering: .releasing)
            }
            return noErr
        }

        // Get data from jitter buffer
        let hasData = jitterBuffer.dequeue(
            intoLeft: leftBuffer,
            intoRight: rightBuffer,
            frameCount: requestedFrames
        )

        let currentGain = fadeGainLock.withLock { $0 }

        if hasData {
            // Data available — apply fade-in if recovering from underflow
            if currentGain < 1.0 {
                applyFadeInNonInterleaved(left: leftBuffer, right: rightBuffer, frameCount: requestedFrames)
            }
            silence.pointee = false
        } else {
            // Underflow — apply fade-out for smooth transition
            if currentGain > 0 {
                applyFadeOutNonInterleaved(left: leftBuffer, right: rightBuffer, frameCount: requestedFrames)
                silence.pointee = false
            } else {
                fillSilenceNonInterleaved(left: leftBuffer, right: rightBuffer, frameCount: requestedFrames)
                silence.pointee = true
            }
        }

        return noErr
    }

    // MARK: - Fade Helpers (Non-Interleaved, SIMD-optimized)

    nonisolated private func applyFadeInNonInterleaved(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        let fadeGain = fadeGainLock.withLock { $0 }
        let samplesToFullGain = Int(ceil((1.0 - fadeGain) / fadeStepPerSample))
        let fadeSamples = min(samplesToFullGain, frameCount)

        if fadeSamples > 0 {
            var startGain = fadeGain
            let endGain = min(1.0, fadeGain + Float(fadeSamples) * fadeStepPerSample)
            var step = fadeStepPerSample

            vDSP_vrampmul(left, 1, &startGain, &step, left, 1, vDSP_Length(fadeSamples))

            startGain = fadeGain
            vDSP_vrampmul(right, 1, &startGain, &step, right, 1, vDSP_Length(fadeSamples))

            fadeGainLock.withLock { fadeGain in fadeGain = endGain }
        }
    }

    nonisolated private func applyFadeOutNonInterleaved(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        let fadeGain = fadeGainLock.withLock { $0 }
        let samplesToZero = Int(ceil(fadeGain / fadeStepPerSample))
        let fadeSamples = min(samplesToZero, frameCount)

        if fadeSamples > 0 {
            var negativeStep = -fadeStepPerSample
            var startGain = fadeGain
            let endGain = max(0.0, fadeGain - Float(fadeSamples) * fadeStepPerSample)

            vDSP_vrampmul(left, 1, &startGain, &negativeStep, left, 1, vDSP_Length(fadeSamples))

            startGain = fadeGain
            vDSP_vrampmul(right, 1, &startGain, &negativeStep, right, 1, vDSP_Length(fadeSamples))

            fadeGainLock.withLock { fadeGain in fadeGain = endGain }
        }

        // Clear rest with silence (SIMD)
        if fadeSamples < frameCount {
            vDSP_vclr(left.advanced(by: fadeSamples), 1, vDSP_Length(frameCount - fadeSamples))
            vDSP_vclr(right.advanced(by: fadeSamples), 1, vDSP_Length(frameCount - fadeSamples))
        }
    }

    nonisolated private func fillSilenceNonInterleaved(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        vDSP_vclr(left, 1, vDSP_Length(frameCount))
        vDSP_vclr(right, 1, vDSP_Length(frameCount))
    }
}

// MARK: - AudioDecoderDelegate

extension AudioProjectionSession: AudioDecoderDelegate {
    nonisolated func audioDecoder(_ decoder: AudioDecoder, didDecode frame: DecodedAudioFrame) {
        // jitterBuffer 는 nonisolated let + 내부 lock (Rule G 예외) 으로 thread-safe.
        // isStartedFlag 만 체크하고 직접 enqueue — actor hop 없음.
        guard isStartedFlag.load(ordering: .acquiring) else { return }
        jitterBuffer.enqueue(frame)
    }

    nonisolated func audioDecoder(_ decoder: AudioDecoder, didFailWith error: Error) {
        // 에러 로깅 + 이벤트 전송.
        continuation.yield(.errorOccurred(error, fatal: false))
    }
}

