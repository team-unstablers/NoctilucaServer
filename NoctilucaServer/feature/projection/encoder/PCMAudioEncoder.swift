//
//  PCMAudioEncoder.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/28/26.
//

import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox

import SiriusKit

/// G.711 mu-law/A-law encoder using AVAudioConverter.
/// Performs resampling (48kHz -> 8kHz) and channel downmix (stereo -> mono).
final class PCMAudioEncoder: NSObject, AudioEncoder {
    private let logger = NoctilucaLogger(category: "PCMAudioEncoder")
    private let workerQueue: DispatchQueue

    private var configuration: AudioEncoderConfiguration?
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var outputFormat: AVAudioFormat?

    private var isStarted = false
    private var frameCounter: UInt64 = 0

    let events: AsyncStream<AudioEncoderEvent>
    private let continuation: AsyncStream<AudioEncoderEvent>.Continuation

    override init() {
        self.workerQueue = DispatchQueue(label: "tech.unstablers.noctiluca.pcmaudioencoder.worker")

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

        guard fourCC == .pcmu || fourCC == .pcma else {
            throw AudioEncoderError.unsupportedCodec(fourCC.stringRepresentation)
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
            self.inputFormat = nil
            self.outputFormat = nil
            self.isStarted = false
        }
        continuation.finish()
    }

    func flush() throws {
        // G.711 has no internal buffering to flush
    }

    func encode(sampleBuffer: CMSampleBuffer) throws {
        guard isStarted else { throw AudioEncoderError.notStarted }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { throw AudioEncoderError.invalidSampleBuffer }

        workerQueue.sync {
            do {
                let converter = try ensureConverter(for: sampleBuffer)
                try performConversion(sampleBuffer: sampleBuffer, converter: converter)
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

        // Create output format for G.711 (8kHz, mono)
        let formatID: AudioFormatID = configuration.codec.fourCC == .pcmu ? kAudioFormatULaw : kAudioFormatALaw

        var outputASBD = AudioStreamBasicDescription(
            mSampleRate: 8000,
            mFormatID: formatID,
            mFormatFlags: 0,
            mBytesPerPacket: 1,
            mFramesPerPacket: 1,
            mBytesPerFrame: 1,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 8,
            mReserved: 0
        )

        guard let outputFormat = AVAudioFormat(streamDescription: &outputASBD) else {
            throw AudioEncoderError.unsupportedFormat
        }
        self.outputFormat = outputFormat

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioEncoderError.converterCreationFailed
        }

        self.converter = converter
        logger.info("Created G.711 converter: \(inputFormat.sampleRate)Hz -> 8000Hz, \(inputFormat.channelCount)ch -> 1ch")

        return converter
    }

    private func performConversion(sampleBuffer: CMSampleBuffer, converter: AVAudioConverter) throws {
        guard let inputFormat = self.inputFormat,
              let outputFormat = self.outputFormat else {
            throw AudioEncoderError.notPrepared
        }

        // Convert CMSampleBuffer to AVAudioPCMBuffer
        guard let inputBuffer = createPCMBuffer(from: sampleBuffer, format: inputFormat) else {
            throw AudioEncoderError.invalidSampleBuffer
        }

        // Calculate output frame count after resampling
        let inputFrameCount = inputBuffer.frameLength
        let outputFrameCount = AVAudioFrameCount(Double(inputFrameCount) * (outputFormat.sampleRate / inputFormat.sampleRate))

        guard outputFrameCount > 0 else {
            return
        }

        // Create output buffer
        let outputBuffer = AVAudioCompressedBuffer(format: outputFormat, packetCapacity: outputFrameCount, maximumPacketSize: 1)

        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let error = conversionError {
            throw AudioEncoderError.conversionFailed(error)
        }

        guard status != .error else {
            throw AudioEncoderError.internalError("Conversion returned error status")
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
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
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

// MARK: - CodecFourCC Extension

extension CodecFourCC {
    /// G.711 mu-law (PCMU)
    static let pcmu = CodecFourCC("P", "C", "M", "U")
    /// G.711 A-law (PCMA)
    static let pcma = CodecFourCC("P", "C", "M", "A")
    /// Opus audio codec
    static let opus = CodecFourCC("O", "P", "U", "S")
}
