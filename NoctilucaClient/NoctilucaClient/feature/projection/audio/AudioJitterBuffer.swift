//
//  AudioJitterBuffer.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/28/26.
//

import Foundation
import AVFoundation
import CoreMedia
import Accelerate
import os

/// A jitter buffer that stores decoded audio frames and provides them
/// to the audio render callback based on PTS timing.
///
/// This buffer handles:
/// - PTS-based frame ordering
/// - Late frame detection and skipping
/// - Buffering state management (buffering → playing → underflow)
/// - Clock synchronization between remote PTS and local playback time
final class AudioJitterBuffer {

    // MARK: - Configuration

    /// Minimum buffer duration in milliseconds before starting playback.
    var minBufferMs: Int = 60

    /// Maximum buffer duration in milliseconds (frames beyond this are dropped).
    var maxBufferMs: Int = 200

    /// Late threshold in milliseconds. Frames older than this are skipped.
    var lateThresholdMs: Int = 40

    // MARK: - State

    enum State {
        case buffering
        case playing
        case underflow
    }

    private(set) var state: State = .buffering

    // MARK: - Clock Synchronization

    /// The anchor point for remote PTS to local time mapping.
    private var anchorRemotePTS: CMTime?

    /// The local host time when the anchor was set.
    private var anchorHostTime: UInt64?

    // MARK: - Buffer Storage

    /// Ring buffer for audio samples (pre-allocated).
    private var ringBuffer: UnsafeMutablePointer<Float>

    /// Ring buffer capacity in frames (stereo samples).
    private let ringBufferCapacity: Int

    /// Number of channels (stereo = 2).
    private let channelCount: Int = 2

    /// Read position in the ring buffer.
    private var readPosition: Int = 0

    /// Write position in the ring buffer.
    private var writePosition: Int = 0

    /// Number of valid samples in the buffer.
    private var availableSamples: Int = 0

    /// Sample rate for time calculations.
    private let sampleRate: Double

    /// Lock for thread-safe access (os_unfair_lock for real-time safety).
    private var lock = os_unfair_lock()

    /// Logger for debugging.
    private let logger = OSLog(subsystem: "pl.unstabler.noctiluca.NoctilucaClient", category: "AudioJitterBuffer")

    // MARK: - Statistics

    private var totalFramesEnqueued: Int = 0
    private var totalFramesDropped: Int = 0
    private var totalLateFramesSkipped: Int = 0

    // MARK: - Initialization

    /// Creates a new jitter buffer.
    /// - Parameters:
    ///   - sampleRate: The sample rate in Hz (default: 48000).
    ///   - maxDurationMs: Maximum buffer duration in milliseconds (default: 500ms).
    init(sampleRate: Double = 48000, maxDurationMs: Int = 500) {
        self.sampleRate = sampleRate

        // Calculate ring buffer capacity
        // maxDurationMs worth of stereo samples
        let maxSamples = Int(sampleRate * Double(maxDurationMs) / 1000.0) * channelCount
        self.ringBufferCapacity = maxSamples

        // Pre-allocate ring buffer
        self.ringBuffer = UnsafeMutablePointer<Float>.allocate(capacity: maxSamples)
        self.ringBuffer.initialize(repeating: 0, count: maxSamples)
    }

    deinit {
        ringBuffer.deallocate()
    }

    // MARK: - Public Methods

    /// Enqueues a decoded audio frame into the buffer.
    /// Called from the decoder thread.
    /// - Parameter frame: The decoded audio frame.
    func enqueue(_ frame: DecodedAudioFrame) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        guard let floatData = frame.pcmBuffer.floatChannelData else {
            os_log(.error, log: logger, "Frame has no float channel data")
            return
        }

        let frameCount = Int(frame.pcmBuffer.frameLength)
        let totalSamples = frameCount * channelCount

        // Check if buffer is full (overflow)
        let maxSamples = Int(sampleRate * Double(maxBufferMs) / 1000.0) * channelCount
        if availableSamples + totalSamples > maxSamples {
            // Drop oldest samples to make room
            let samplesToDiscard = (availableSamples + totalSamples) - maxSamples
            readPosition = (readPosition + samplesToDiscard) % ringBufferCapacity
            availableSamples -= samplesToDiscard
            totalFramesDropped += 1
            os_log(.debug, log: logger, "Buffer overflow, dropped %d samples", samplesToDiscard)
        }

        // Set anchor on first frame
        if anchorRemotePTS == nil {
            setAnchorLocked(remotePTS: frame.pts)
        }

        // Check for late frames (only when playing)
        if state == .playing {
            let lateness = latenessLocked(of: frame.pts)
            if lateness > Double(lateThresholdMs) / 1000.0 {
                totalLateFramesSkipped += 1
                os_log(.debug, log: logger, "Skipping late frame: %.1f ms late", lateness * 1000)
                return
            }
        }

        // Copy interleaved samples to ring buffer using vDSP
        // AVAudioPCMBuffer is non-interleaved, so we need to interleave
        let channels = Int(frame.pcmBuffer.format.channelCount)

        if channels >= 2 {
            // Stereo: use SIMD interleaving
            interleaveLocked(from: floatData[0], and: floatData[1], frameCount: frameCount)
        } else {
            // Mono: duplicate to both channels
            // Use vDSP to copy mono to both L and R
            let monoData = floatData[0]
            for i in 0..<frameCount {
                let writeIdx = (writePosition + i * channelCount) % ringBufferCapacity
                ringBuffer[writeIdx] = monoData[i]
                ringBuffer[(writeIdx + 1) % ringBufferCapacity] = monoData[i]
            }
        }

        writePosition = (writePosition + totalSamples) % ringBufferCapacity
        availableSamples += totalSamples
        totalFramesEnqueued += 1

        // Check if we have enough data to start playing
        if state == .buffering {
            let bufferedMs = Double(availableSamples / channelCount) / sampleRate * 1000.0
            if bufferedMs >= Double(minBufferMs) {
                state = .playing
                os_log(.info, log: logger, "Buffering complete, starting playback (%.1f ms buffered)", bufferedMs)
            }
        } else if state == .underflow {
            let bufferedMs = Double(availableSamples / channelCount) / sampleRate * 1000.0
            if bufferedMs >= Double(minBufferMs) {
                state = .playing
                os_log(.info, log: logger, "Recovered from underflow (%.1f ms buffered)", bufferedMs)
            }
        }
    }

    /// Dequeues samples for the render callback (interleaved output).
    /// Called from the real-time audio thread.
    /// - Parameter frameCount: Number of frames requested.
    /// - Returns: true if data was available, false if underflow.
    func dequeue(into buffer: UnsafeMutablePointer<Float>, frameCount: Int) -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let requestedSamples = frameCount * channelCount

        if state == .buffering {
            // Still buffering, output silence
            return false
        }

        if availableSamples < requestedSamples {
            // Underflow
            if state == .playing {
                state = .underflow
                os_log(.debug, log: logger, "Underflow detected, available: %d, requested: %d", availableSamples, requestedSamples)
            }

            // Output whatever we have, then silence
            if availableSamples > 0 {
                copyFromRingBufferLocked(to: buffer, count: availableSamples)
                // Fill rest with silence
                for i in availableSamples..<requestedSamples {
                    buffer[i] = 0
                }
                readPosition = (readPosition + availableSamples) % ringBufferCapacity
                availableSamples = 0
            }
            return false
        }

        // Normal case: enough data available
        copyFromRingBufferLocked(to: buffer, count: requestedSamples)
        readPosition = (readPosition + requestedSamples) % ringBufferCapacity
        availableSamples -= requestedSamples

        return true
    }

    /// Dequeues samples for the render callback (non-interleaved output).
    /// Called from the real-time audio thread.
    /// Uses vDSP for SIMD-optimized deinterleaving.
    /// - Parameters:
    ///   - intoLeft: Left channel output buffer.
    ///   - intoRight: Right channel output buffer.
    ///   - frameCount: Number of frames requested.
    /// - Returns: true if data was available, false if underflow.
    func dequeue(
        intoLeft leftBuffer: UnsafeMutablePointer<Float>,
        intoRight rightBuffer: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) -> Bool {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let requestedSamples = frameCount * channelCount

        if state == .buffering {
            // Still buffering, output silence (SIMD clear)
            vDSP_vclr(leftBuffer, 1, vDSP_Length(frameCount))
            vDSP_vclr(rightBuffer, 1, vDSP_Length(frameCount))
            return false
        }

        if availableSamples < requestedSamples {
            // Underflow
            if state == .playing {
                state = .underflow
                os_log(.debug, log: logger, "Underflow detected, available: %d, requested: %d", availableSamples, requestedSamples)
            }

            // Output whatever we have (deinterleaved), then silence
            let availableFrames = availableSamples / channelCount
            if availableFrames > 0 {
                deinterleaveLocked(to: leftBuffer, and: rightBuffer, frameCount: availableFrames)
            }
            // Fill rest with silence (SIMD clear)
            if availableFrames < frameCount {
                vDSP_vclr(leftBuffer.advanced(by: availableFrames), 1, vDSP_Length(frameCount - availableFrames))
                vDSP_vclr(rightBuffer.advanced(by: availableFrames), 1, vDSP_Length(frameCount - availableFrames))
            }
            readPosition = (readPosition + availableSamples) % ringBufferCapacity
            availableSamples = 0
            return false
        }

        // Normal case: enough data available - deinterleave to separate buffers
        deinterleaveLocked(to: leftBuffer, and: rightBuffer, frameCount: frameCount)
        readPosition = (readPosition + requestedSamples) % ringBufferCapacity
        availableSamples -= requestedSamples

        return true
    }

    /// Returns the current buffer level in milliseconds.
    var bufferLevelMs: Double {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return Double(availableSamples / channelCount) / sampleRate * 1000.0
    }

    /// Resets the buffer state.
    func reset() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        readPosition = 0
        writePosition = 0
        availableSamples = 0
        state = .buffering
        anchorRemotePTS = nil
        anchorHostTime = nil

        // Clear buffer using vDSP (SIMD)
        vDSP_vclr(ringBuffer, 1, vDSP_Length(ringBufferCapacity))

        os_log(.info, log: logger, "Buffer reset")
    }

    // MARK: - Private Methods

    /// Sets the anchor point for clock synchronization.
    /// Must be called with lock held.
    private func setAnchorLocked(remotePTS: CMTime) {
        anchorRemotePTS = remotePTS
        anchorHostTime = mach_absolute_time()
        os_log(.debug, log: logger, "Anchor set: remote PTS = %.3f", remotePTS.seconds)
    }

    /// Calculates how late a frame is compared to the expected playback time.
    /// Must be called with lock held.
    /// - Parameter remotePTS: The remote PTS of the frame.
    /// - Returns: Lateness in seconds (positive = late, negative = early).
    private func latenessLocked(of remotePTS: CMTime) -> TimeInterval {
        guard let anchorPTS = anchorRemotePTS,
              let anchorHost = anchorHostTime else {
            return 0
        }

        // Convert mach_absolute_time to seconds
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)

        let currentHost = mach_absolute_time()
        let elapsedNanos = (currentHost - anchorHost) * UInt64(timebaseInfo.numer) / UInt64(timebaseInfo.denom)
        let elapsedSeconds = Double(elapsedNanos) / 1_000_000_000.0

        // Expected remote PTS at current time
        let expectedPTS = anchorPTS.seconds + elapsedSeconds

        // Lateness = expected - actual (positive means the frame is late)
        return expectedPTS - remotePTS.seconds
    }

    /// Copies samples from the ring buffer.
    /// Must be called with lock held.
    private func copyFromRingBufferLocked(to buffer: UnsafeMutablePointer<Float>, count: Int) {
        let firstChunkSize = min(count, ringBufferCapacity - readPosition)

        // Copy first chunk
        buffer.update(from: ringBuffer.advanced(by: readPosition), count: firstChunkSize)

        // Copy second chunk if wrapped around
        if firstChunkSize < count {
            let secondChunkSize = count - firstChunkSize
            buffer.advanced(by: firstChunkSize).update(from: ringBuffer, count: secondChunkSize)
        }
    }

    /// Deinterleaves samples from ring buffer to separate L/R buffers using vDSP.
    /// Must be called with lock held.
    /// - Parameters:
    ///   - leftBuffer: Destination for left channel samples.
    ///   - rightBuffer: Destination for right channel samples.
    ///   - frameCount: Number of frames to deinterleave.
    private func deinterleaveLocked(
        to leftBuffer: UnsafeMutablePointer<Float>,
        and rightBuffer: UnsafeMutablePointer<Float>,
        frameCount: Int
    ) {
        let totalSamples = frameCount * channelCount
        let firstChunkSamples = min(totalSamples, ringBufferCapacity - readPosition)
        let firstChunkFrames = firstChunkSamples / channelCount

        // Use vDSP_ctoz for SIMD deinterleaving (treats stereo as complex: L=real, R=imag)
        // First chunk (contiguous)
        if firstChunkFrames > 0 {
            var splitComplex = DSPSplitComplex(realp: leftBuffer, imagp: rightBuffer)
            vDSP_ctoz(
                UnsafePointer<DSPComplex>(OpaquePointer(ringBuffer.advanced(by: readPosition))),
                2,  // stride in the interleaved buffer (2 floats per complex)
                &splitComplex,
                1,  // stride in the split buffers
                vDSP_Length(firstChunkFrames)
            )
        }

        // Second chunk if wrapped around
        if firstChunkFrames < frameCount {
            let remainingFrames = frameCount - firstChunkFrames
            var splitComplex = DSPSplitComplex(
                realp: leftBuffer.advanced(by: firstChunkFrames),
                imagp: rightBuffer.advanced(by: firstChunkFrames)
            )
            vDSP_ctoz(
                UnsafePointer<DSPComplex>(OpaquePointer(ringBuffer)),
                2,
                &splitComplex,
                1,
                vDSP_Length(remainingFrames)
            )
        }
    }

    /// Interleaves samples from separate L/R buffers to ring buffer using vDSP.
    /// Must be called with lock held.
    /// - Parameters:
    ///   - leftBuffer: Source left channel samples.
    ///   - rightBuffer: Source right channel samples.
    ///   - frameCount: Number of frames to interleave.
    private func interleaveLocked(
        from leftBuffer: UnsafePointer<Float>,
        and rightBuffer: UnsafePointer<Float>,
        frameCount: Int
    ) {
        let totalSamples = frameCount * channelCount
        let firstChunkSamples = min(totalSamples, ringBufferCapacity - writePosition)
        let firstChunkFrames = firstChunkSamples / channelCount

        // Use vDSP_ztoc for SIMD interleaving (treats stereo as complex: L=real, R=imag)
        // First chunk (contiguous)
        if firstChunkFrames > 0 {
            var splitComplex = DSPSplitComplex(
                realp: UnsafeMutablePointer(mutating: leftBuffer),
                imagp: UnsafeMutablePointer(mutating: rightBuffer)
            )
            vDSP_ztoc(
                &splitComplex,
                1,  // stride in the split buffers
                UnsafeMutablePointer<DSPComplex>(OpaquePointer(ringBuffer.advanced(by: writePosition))),
                2,  // stride in the interleaved buffer
                vDSP_Length(firstChunkFrames)
            )
        }

        // Second chunk if wrapped around
        if firstChunkFrames < frameCount {
            let remainingFrames = frameCount - firstChunkFrames
            var splitComplex = DSPSplitComplex(
                realp: UnsafeMutablePointer(mutating: leftBuffer.advanced(by: firstChunkFrames)),
                imagp: UnsafeMutablePointer(mutating: rightBuffer.advanced(by: firstChunkFrames))
            )
            vDSP_ztoc(
                &splitComplex,
                1,
                UnsafeMutablePointer<DSPComplex>(OpaquePointer(ringBuffer)),
                2,
                vDSP_Length(remainingFrames)
            )
        }
    }
}
