//
//  OpusAudioEncoder.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/28/26.
//

import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox

import SiriusKit

/// Opus encoder using AVAudioConverter.
/// Supports 48kHz stereo input with configurable bitrate.
final class OpusAudioEncoder: NSObject, AudioEncoder {
    private let logger = NoctilucaLogger(category: "OpusAudioEncoder")
    private let workerQueue: DispatchQueue

    private var configuration: AudioEncoderConfiguration?
    private var converter: AVAudioConverter?
    private var resamplerConverter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var intermediateFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?

    /// Internal buffer for accumulating samples (Opus requires 20ms frames = 960 samples @ 48kHz)
    private var accumulationBuffer: AVAudioPCMBuffer?
    private var accumulatedFrameCount: AVAudioFrameCount = 0

    /// Opus frame size in samples (20ms @ 48kHz = 960 samples)
    private let opusFrameSamples: AVAudioFrameCount = 960

    private var isStarted = false
    private var frameCounter: UInt64 = 0

    /// Default bitrate for Opus encoding (kbps)
    private var targetBitrateKbps: Int = 64

    let events: AsyncStream<AudioEncoderEvent>
    private let continuation: AsyncStream<AudioEncoderEvent>.Continuation

    override init() {
        self.workerQueue = DispatchQueue(label: "app.noctiluca.server.projection.encoder.opus.worker", qos: .userInitiated)

        var continuationLocal: AsyncStream<AudioEncoderEvent>.Continuation!
        self.events = AsyncStream<AudioEncoderEvent>(AudioEncoderEvent.self, bufferingPolicy: .unbounded) { continuation in
            continuationLocal = continuation
        }
        self.continuation = continuationLocal

        super.init()
    }

    func prepare(with configuration: AudioEncoderConfiguration) throws {
        guard self.configuration == nil else {
            throw AudioEncoderError.alreadyPrepared
        }

        let codec = configuration.codec
        let fourCC = codec.fourCC

        guard fourCC == .opus else {
            throw AudioEncoderError.unsupportedCodec(fourCC.stringRepresentation)
        }

        // Extract bitrate from codec quality settings
        switch codec.quality {
        case .constantBitrate(let bitrateKbps):
            self.targetBitrateKbps = Int(bitrateKbps)
        case .variableBitrate(let targetBitrateKbps, _):
            self.targetBitrateKbps = Int(targetBitrateKbps)
        case .auto:
            self.targetBitrateKbps = 64 // Default
        }

        self.configuration = configuration
    }

    func start() throws {
        guard configuration != nil else {
            throw AudioEncoderError.notPrepared
        }
        isStarted = true
    }

    func stop() throws {
        workerQueue.sync {
            self.converter = nil
            self.resamplerConverter = nil
            self.inputFormat = nil
            self.intermediateFormat = nil
            self.outputFormat = nil
            self.accumulationBuffer = nil
            self.accumulatedFrameCount = 0
            self.isStarted = false
        }
        continuation.finish()
    }

    func flush() throws {
        workerQueue.sync {
            // Encode any remaining accumulated samples
            if let converter = self.converter,
               let buffer = self.accumulationBuffer,
               self.accumulatedFrameCount > 0 {
                do {
                    // Pad with silence if needed
                    let framesToEncode = self.opusFrameSamples
                    if self.accumulatedFrameCount < framesToEncode {
                        // Zero out remaining frames
                        if let floatData = buffer.floatChannelData {
                            for channel in 0..<Int(buffer.format.channelCount) {
                                let startFrame = Int(self.accumulatedFrameCount)
                                let endFrame = Int(framesToEncode)
                                for frame in startFrame..<endFrame {
                                    floatData[channel][frame] = 0
                                }
                            }
                        }
                        buffer.frameLength = framesToEncode
                    }

                    try encodeAccumulatedBuffer(converter: converter, pts: .invalid)
                } catch {
                    continuation.yield(.errorOccurred(error))
                }
            }
            self.accumulatedFrameCount = 0
        }
    }

    func encode(sampleBuffer: CMSampleBuffer) throws {
        guard isStarted else { throw AudioEncoderError.notStarted }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { throw AudioEncoderError.invalidSampleBuffer }

        workerQueue.sync {
            do {
                let converter = try ensureConverter(for: sampleBuffer)
                try accumulateAndEncode(sampleBuffer: sampleBuffer, converter: converter)
            } catch {
                continuation.yield(.errorOccurred(error))
            }
        }
    }

    // MARK: - Private Methods

    private func ensureConverter(for sampleBuffer: CMSampleBuffer) throws -> AVAudioConverter {
        if let converter = self.converter {
            return converter
        }

        guard let configuration = self.configuration else {
            throw AudioEncoderError.notPrepared
        }

        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw AudioEncoderError.invalidSampleBuffer
        }

        guard let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            throw AudioEncoderError.invalidSampleBuffer
        }

        // Create input format from sample buffer
        guard let inputFormat = AVAudioFormat(streamDescription: asbdPtr) else {
            throw AudioEncoderError.unsupportedFormat
        }
        self.inputFormat = inputFormat

        let opusSampleRate: Double = 48000.0
        let outputChannelCount = min(inputFormat.channelCount, 2)

        // Stage 1: Create resampler if input is not 48kHz
        let converterInputFormat: AVAudioFormat
        if inputFormat.sampleRate != opusSampleRate {
            guard let intFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: opusSampleRate,
                channels: outputChannelCount,
                interleaved: false
            ) else {
                throw AudioEncoderError.unsupportedFormat
            }
            self.intermediateFormat = intFormat

            guard let resampler = AVAudioConverter(from: inputFormat, to: intFormat) else {
                throw AudioEncoderError.converterCreationFailed
            }
            self.resamplerConverter = resampler
            converterInputFormat = intFormat
        } else {
            self.intermediateFormat = nil
            self.resamplerConverter = nil
            converterInputFormat = inputFormat
        }

        // Stage 2: Create Opus converter from 48kHz PCM -> Opus
        var outputASBD = AudioStreamBasicDescription(
            mSampleRate: opusSampleRate,
            mFormatID: kAudioFormatOpus,
            mFormatFlags: 0,
            mBytesPerPacket: 0, // Variable
            mFramesPerPacket: opusFrameSamples, // 20ms @ 48kHz
            mBytesPerFrame: 0, // Variable
            mChannelsPerFrame: outputChannelCount,
            mBitsPerChannel: 0, // Variable
            mReserved: 0
        )

        guard let outputFormat = AVAudioFormat(streamDescription: &outputASBD) else {
            throw AudioEncoderError.unsupportedFormat
        }
        self.outputFormat = outputFormat

        guard let converter = AVAudioConverter(from: converterInputFormat, to: outputFormat) else {
            throw AudioEncoderError.converterCreationFailed
        }

        // Set bitrate
        converter.bitRate = targetBitrateKbps * 1000

        self.converter = converter

        // Create accumulation buffer in 48kHz format (converterInputFormat is always 48kHz)
        guard let accBuffer = AVAudioPCMBuffer(pcmFormat: converterInputFormat, frameCapacity: opusFrameSamples * 4) else {
            throw AudioEncoderError.internalError("Failed to create accumulation buffer")
        }
        self.accumulationBuffer = accBuffer
        self.accumulatedFrameCount = 0

        if self.resamplerConverter != nil {
            logger.info("Created Opus converter: \(inputFormat.sampleRate)Hz \(inputFormat.channelCount)ch -> [resample to \(opusSampleRate)Hz] -> Opus \(self.targetBitrateKbps)kbps")
        } else {
            logger.info("Created Opus converter: \(inputFormat.sampleRate)Hz \(inputFormat.channelCount)ch -> Opus \(self.targetBitrateKbps)kbps")
        }

        return converter
    }

    private func accumulateAndEncode(sampleBuffer: CMSampleBuffer, converter: AVAudioConverter) throws {
        guard let inputFormat = self.inputFormat,
              let accumulationBuffer = self.accumulationBuffer else {
            throw AudioEncoderError.notPrepared
        }

        // Convert CMSampleBuffer to AVAudioPCMBuffer
        guard let inputBuffer = createPCMBuffer(from: sampleBuffer, format: inputFormat) else {
            throw AudioEncoderError.invalidSampleBuffer
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Resample to 48kHz if needed
        let bufferToAccumulate: AVAudioPCMBuffer
        if let resampler = self.resamplerConverter, let intFormat = self.intermediateFormat {
            let ratio = intFormat.sampleRate / inputFormat.sampleRate
            let resampledFrameCount = AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio))
            guard resampledFrameCount > 0 else { return }

            guard let resampledBuffer = AVAudioPCMBuffer(pcmFormat: intFormat, frameCapacity: resampledFrameCount) else {
                throw AudioEncoderError.internalError("Failed to create resample buffer")
            }

            var conversionError: NSError?
            var inputConsumed = false
            let status = resampler.convert(to: resampledBuffer, error: &conversionError) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                return inputBuffer
            }

            if let error = conversionError {
                throw AudioEncoderError.conversionFailed(error)
            }
            guard status != .error else {
                throw AudioEncoderError.internalError("Resampling failed")
            }

            bufferToAccumulate = resampledBuffer
        } else {
            bufferToAccumulate = inputBuffer
        }

        // Accumulate resampled (48kHz) samples
        var inputOffset: AVAudioFrameCount = 0
        let inputFrameCount = bufferToAccumulate.frameLength
        let channelCount = Int(accumulationBuffer.format.channelCount)

        while inputOffset < inputFrameCount {
            let framesToCopy = min(
                inputFrameCount - inputOffset,
                opusFrameSamples - accumulatedFrameCount
            )

            // Copy frames to accumulation buffer
            if let srcFloatData = bufferToAccumulate.floatChannelData,
               let accFloatData = accumulationBuffer.floatChannelData {
                for channel in 0..<channelCount {
                    let srcPtr = srcFloatData[channel].advanced(by: Int(inputOffset))
                    let dstPtr = accFloatData[channel].advanced(by: Int(accumulatedFrameCount))
                    memcpy(dstPtr, srcPtr, Int(framesToCopy) * MemoryLayout<Float>.size)
                }
            }

            accumulatedFrameCount += framesToCopy
            inputOffset += framesToCopy

            // If we have enough samples, encode
            if accumulatedFrameCount >= opusFrameSamples {
                accumulationBuffer.frameLength = opusFrameSamples
                try encodeAccumulatedBuffer(converter: converter, pts: pts)
                accumulatedFrameCount = 0
            }
        }
    }

    private func encodeAccumulatedBuffer(converter: AVAudioConverter, pts: CMTime) throws {
        guard let outputFormat = self.outputFormat,
              let accumulationBuffer = self.accumulationBuffer else {
            throw AudioEncoderError.notPrepared
        }

        // Create output buffer
        // Opus typically produces ~60-80 bytes per 20ms frame at 64kbps
        let maxPacketSize = 1500
        let outputBuffer = AVAudioCompressedBuffer(format: outputFormat, packetCapacity: 1, maximumPacketSize: maxPacketSize)

        var conversionError: NSError?
        var inputConsumed = false

        let status = converter.convert(to: outputBuffer, error: &conversionError) { inNumPackets, outStatus in
            if inputConsumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            inputConsumed = true
            outStatus.pointee = .haveData
            return self.accumulationBuffer
        }

        if let error = conversionError {
            throw AudioEncoderError.conversionFailed(error)
        }

        guard status != .error else {
            throw AudioEncoderError.internalError("Opus conversion returned error status")
        }

        // Extract encoded data
        let outputData = Data(bytes: outputBuffer.data, count: Int(outputBuffer.byteLength))

        guard !outputData.isEmpty else {
            return
        }

        guard outputData.count <= Int(UInt32.max) else {
            throw AudioEncoderError.payloadTooLarge(outputData.count)
        }

        // Create frame header
        let ptsUs = microseconds(from: pts)

        let header = FrameDataHeader(
            frameID: frameCounter,
            frameLength: UInt32(outputData.count),
            presentationTimestamp: ptsUs,
            flags: []
        )

        frameCounter += 1

        let encodedFrame = EncodedAudioFrame(
            header: header,
            data: outputData
        )

        continuation.yield(.frameEncoded(encodedFrame))
    }

    private func createPCMBuffer(from sampleBuffer: CMSampleBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return nil }

        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        // Get audio buffer list
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            return nil
        }

        var lengthAtOffset: Int = 0
        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?

        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        guard status == kCMBlockBufferNoErr, let dataPointer = dataPointer else {
            return nil
        }

        // Copy data to PCM buffer
        if format.isInterleaved {
            memcpy(pcmBuffer.audioBufferList.pointee.mBuffers.mData, dataPointer, totalLength)
        } else {
            // Non-interleaved: need to handle each channel separately
            let channelCount = Int(format.channelCount)
            let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)

            if channelCount > 0 && bytesPerFrame > 0 {
                let floatChannelData = pcmBuffer.floatChannelData
                let bytesPerChannel = totalLength / channelCount

                for channel in 0..<channelCount {
                    if let channelData = floatChannelData?[channel] {
                        let sourceOffset = channel * bytesPerChannel
                        memcpy(channelData, dataPointer.advanced(by: sourceOffset), bytesPerChannel)
                    }
                }
            }
        }

        return pcmBuffer
    }

    private func microseconds(from time: CMTime) -> UInt64 {
        guard time.isValid, time.timescale != 0 else { return 0 }
        let scaled = CMTimeConvertScale(time, timescale: 1_000_000, method: .default)
        if scaled.value < 0 {
            return 0
        }
        return UInt64(scaled.value)
    }
}
