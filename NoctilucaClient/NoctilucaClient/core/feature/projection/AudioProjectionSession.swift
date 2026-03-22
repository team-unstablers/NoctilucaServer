//
//  AudioProjectionSession.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/28/26.
//

import Foundation
import AVFoundation
import CoreMedia
import Accelerate

import Combine

import SiriusKitClient

enum AudioProjectionSessionEvent: Sendable {
    /// 오류가 발생했습니다.
    case errorOccurred(Error, fatal: Bool)
}

/// Audio projection session that handles audio decoding and playback.
///
/// Uses AVAudioSourceNode (pull-based) with a jitter buffer for accurate
/// PTS-based timing and smooth playback.
class AudioProjectionSession: Identifiable {
    private let logger = SiriusLogger(category: "AudioProjectionSession", subsystem: "app.noctiluca.client")

    let id: UUID
    weak var dataChannel: ProjectionDataChannel?
    weak var controlChannel: ProjectionChannel?

    private(set) var decoder: (any AudioDecoder)?
    private(set) var codec: SiriusKitClient.AudioCodec?

    // MARK: - AVAudioEngine

    private var sourceNode: AVAudioSourceNode?

    /// Output format for the audio engine (48kHz, stereo, Float32)
    private var outputFormat: AVAudioFormat?

    // MARK: - Jitter Buffer

    /// Jitter buffer for PTS-based timing control.
    private var jitterBuffer: AudioJitterBuffer!

    // MARK: - Fade Control (for smooth underflow handling)

    /// Current fade gain (0.0 = silent, 1.0 = full volume).
    private var fadeGain: Float = 1.0

    /// Fade step per sample for smooth transitions.
    private var fadeStepPerSample: Float = 1.0 / 480.0  // ~10ms fade at 48kHz

    private var isStarted: Bool = false

    /// stop() 호출 시 true — render callback에서 fade-out을 수행하도록 신호
    private var isStopping: Bool = false

    /// render callback이 fade-out을 완료했음을 알리는 플래그
    private var fadeOutComplete: Bool = false

    private let audioJitterBufferPreset: AudioJitterBuffer.Preset

    let events = PassthroughSubject<AudioProjectionSessionEvent, Never>()

    // MARK: - Lifecycle

    init(id: UUID, dataChannel: ProjectionDataChannel, controlChannel: ProjectionChannel, audioJitterBufferPreset: AudioJitterBuffer.Preset = .latencyFirst) {
        self.id = id
        self.dataChannel = dataChannel
        self.controlChannel = controlChannel
        self.audioJitterBufferPreset = audioJitterBufferPreset

        self.dataChannel?.delegate = self
        self.dataChannel?.activate()
    }

    deinit {
        try? stop()
    }

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

        // Setup source node (formerly setupAudioEngine)
        try setupSourceNode()

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
        fadeGain = 1.0
        isStopping = false
        fadeOutComplete = false

        try decoder.start()

        do {
            // Attach to shared engine
            try await NOCAudioEngine.shared.attach(sourceNode, format: outputFormat)
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
            throw error
        }

        isStarted = true

        logger.info("AudioProjectionSession started (jitter buffer mode)")
    }

    /// Stops audio decoding and playback.
    func stop() throws {
        guard isStarted || isStopping else { return }
        isStarted = false

        if sourceNode != nil {
            // render callback에서 fade-out을 수행하도록 신호
            // jitter buffer는 아직 reset하지 않음 — render callback이 남은 데이터를 fade-out에 사용
            isStopping = true
            fadeOutComplete = false

            // render callback이 fade-out을 완료할 때까지 대기 (최대 ~30ms)
            // fade-out은 ~10ms (480 samples @ 48kHz)
            let maxWaitUs: useconds_t = 30_000
            let stepUs: useconds_t = 1_000
            var waited: useconds_t = 0
            while !fadeOutComplete && waited < maxWaitUs {
                usleep(stepUs)
                waited += stepUs
            }

            isStopping = false
        }

        if let sourceNode = sourceNode {
            NOCAudioEngine.shared.detach(sourceNode)
        }

        try decoder?.stop()
        decoder = nil

        jitterBuffer?.reset()

        logger.info("AudioProjectionSession stopped")
    }

    // MARK: - Audio Engine Setup

    private func setupSourceNode() throws {
        // Create output format (48kHz, stereo, Float32, NON-INTERLEAVED)
        // AVAudioEngine prefers non-interleaved format internally
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2) else {
            throw AudioDecoderError.unsupportedFormat
        }
        self.outputFormat = format

        // Initialize jitter buffer
        jitterBuffer = AudioJitterBuffer(sampleRate: 48000, maxDurationMs: 500, preset: audioJitterBufferPreset)

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

    // MARK: - Render Callback

    /// Audio render callback. Called from the real-time audio thread.
    /// - Warning: This runs on a real-time thread. Avoid memory allocation, locks, and Objective-C dispatch.
    private func renderCallback(
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

        // stop() 호출 시: 남은 데이터를 fade-out하며 재생
        if isStopping {
            if fadeGain > 0 {
                let _ = jitterBuffer.dequeue(intoLeft: leftBuffer, intoRight: rightBuffer, frameCount: requestedFrames)
                applyFadeOutNonInterleaved(left: leftBuffer, right: rightBuffer, frameCount: requestedFrames)
                silence.pointee = false
            } else {
                fillSilenceNonInterleaved(left: leftBuffer, right: rightBuffer, frameCount: requestedFrames)
                silence.pointee = true
                fadeOutComplete = true
            }
            return noErr
        }

        // Get interleaved data from jitter buffer into temp storage
        // We need to deinterleave: L R L R L R -> L L L, R R R
        let hasData = jitterBuffer.dequeue(
            intoLeft: leftBuffer,
            intoRight: rightBuffer,
            frameCount: requestedFrames
        )

        if hasData {
            // Data available - apply fade in if recovering from underflow
            if fadeGain < 1.0 {
                applyFadeInNonInterleaved(left: leftBuffer, right: rightBuffer, frameCount: requestedFrames)
            }
            silence.pointee = false
        } else {
            // Underflow - apply fade out for smooth transition
            if fadeGain > 0 {
                applyFadeOutNonInterleaved(left: leftBuffer, right: rightBuffer, frameCount: requestedFrames)
                silence.pointee = false
            } else {
                // Already faded out, output silence
                fillSilenceNonInterleaved(left: leftBuffer, right: rightBuffer, frameCount: requestedFrames)
                silence.pointee = true
            }
        }

        return noErr
    }

    // MARK: - Fade Helpers (Non-Interleaved, SIMD-optimized)

    /// Applies fade-in to non-interleaved audio buffers using vDSP.
    private func applyFadeInNonInterleaved(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        // Calculate how many samples until we reach full gain
        let samplesToFullGain = Int(ceil((1.0 - fadeGain) / fadeStepPerSample))
        let fadeSamples = min(samplesToFullGain, frameCount)

        if fadeSamples > 0 {
            // Use vDSP_vrampmul for SIMD ramp multiplication
            var startGain = fadeGain
            var endGain = min(1.0, fadeGain + Float(fadeSamples) * fadeStepPerSample)

            // Apply ramp to left channel
            vDSP_vrampmul(left, 1, &startGain, &fadeStepPerSample, left, 1, vDSP_Length(fadeSamples))

            // Apply ramp to right channel (reset startGain)
            startGain = fadeGain
            vDSP_vrampmul(right, 1, &startGain, &fadeStepPerSample, right, 1, vDSP_Length(fadeSamples))

            fadeGain = endGain
        }

        // Rest of the samples are at full gain (no modification needed)
    }

    /// Applies fade-out to non-interleaved audio buffers using vDSP.
    private func applyFadeOutNonInterleaved(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        // Calculate how many samples until we reach zero
        let samplesToZero = Int(ceil(fadeGain / fadeStepPerSample))
        let fadeSamples = min(samplesToZero, frameCount)

        if fadeSamples > 0 {
            var negativeStep = -fadeStepPerSample
            var startGain = fadeGain
            let endGain = max(0.0, fadeGain - Float(fadeSamples) * fadeStepPerSample)

            // Apply negative ramp to left channel
            vDSP_vrampmul(left, 1, &startGain, &negativeStep, left, 1, vDSP_Length(fadeSamples))

            // Apply negative ramp to right channel (reset startGain)
            startGain = fadeGain
            vDSP_vrampmul(right, 1, &startGain, &negativeStep, right, 1, vDSP_Length(fadeSamples))

            fadeGain = endGain
        }

        // Clear rest with silence (SIMD)
        if fadeSamples < frameCount {
            vDSP_vclr(left.advanced(by: fadeSamples), 1, vDSP_Length(frameCount - fadeSamples))
            vDSP_vclr(right.advanced(by: fadeSamples), 1, vDSP_Length(frameCount - fadeSamples))
        }
    }

    /// Fills non-interleaved buffers with silence using vDSP.
    private func fillSilenceNonInterleaved(
        left: UnsafeMutablePointer<Float>,
        right: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        vDSP_vclr(left, 1, vDSP_Length(frameCount))
        vDSP_vclr(right, 1, vDSP_Length(frameCount))
    }

    // MARK: - Frame Handling

    /// Handles an encoded audio frame from the data channel.
    func handleEncodedFrame(_ frame: EncodedAudioFrameInput) {
        guard isStarted else { return }

        do {
            try decoder?.decode(frame)
        } catch {
            logger.error("Failed to decode audio frame: \(error.localizedDescription)")
        }
    }
}

// MARK: - AudioDecoderDelegate

extension AudioProjectionSession: AudioDecoderDelegate {
    func audioDecoder(_ decoder: AudioDecoder, didDecode frame: DecodedAudioFrame) {
        guard isStarted else { return }

        // Enqueue to jitter buffer (PTS-based timing handled internally)
        jitterBuffer.enqueue(frame)
    }

    func audioDecoder(_ decoder: AudioDecoder, didFailWith error: Error) {
        logger.error("Audio decoder error: \(error.localizedDescription)")
        Task { @MainActor in
            self.events.send(.errorOccurred(error, fatal: false))
        }
    }
}

// MARK: - ProjectionDataChannelDelegate

extension AudioProjectionSession: ProjectionDataChannelDelegate {
    func projectionDataChannel(_ channel: ProjectionDataChannel, didReceiveFrame frame: consuming EncodedFrameInput) {
        // Audio session ignores video frames
    }

    func projectionDataChannel(_ channel: ProjectionDataChannel, didReceiveAudioFrame frame: consuming EncodedAudioFrameInput) {
        handleEncodedFrame(frame)
    }
}
