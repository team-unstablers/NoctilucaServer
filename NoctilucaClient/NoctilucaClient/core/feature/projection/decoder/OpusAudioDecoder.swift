//
//  OpusAudioDecoder.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/28/26.
//

import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox

import SiriusKitClient

/// Opus decoder using AVAudioConverter.
/// Decodes Opus frames to PCM (48kHz, stereo, Float32).
final class OpusAudioDecoder: NSObject, AudioDecoder {
    private let logger = SiriusLogger(category: "OpusAudioDecoder", subsystem: "pl.unstabler.noctiluca.NoctilucaClient")
    private let workerQueue: DispatchQueue

    weak var delegate: AudioDecoderDelegate?

    private var configuration: AudioDecoderConfiguration?
    private var converter: AVAudioConverter?

    /// Input format: Opus (48kHz, stereo)
    private var inputFormat: AVAudioFormat?

    /// Output format: Linear PCM (48kHz, stereo, Float32)
    private var outputFormat: AVAudioFormat?

    /// Opus frame size in samples (20ms @ 48kHz = 960 samples)
    private let opusFrameSamples: AVAudioFrameCount = 960

    private var isStarted = false

    override init() {
        self.workerQueue = DispatchQueue(label: "tech.unstablers.noctiluca.opusaudiodecoder.worker")
        super.init()
    }

    func prepare(with configuration: AudioDecoderConfiguration) throws {
        guard self.configuration == nil else {
            throw AudioDecoderError.alreadyPrepared
        }

        let codec = configuration.codec
        let fourCC = codec.fourCC

        guard fourCC == .opus else {
            throw AudioDecoderError.unsupportedCodec(fourCC.stringRepresentation)
        }

        self.configuration = configuration
    }

    func start() throws {
        guard configuration != nil else {
            throw AudioDecoderError.notPrepared
        }
        isStarted = true
        logger.info("OpusAudioDecoder started")
    }

    func stop() throws {
        workerQueue.sync {
            self.converter = nil
            self.inputFormat = nil
            self.outputFormat = nil
            self.isStarted = false
        }
        logger.info("OpusAudioDecoder stopped")
    }

    func flush() throws {
        // Reset converter state if needed
        workerQueue.sync {
            converter?.reset()
        }
    }

    func decode(_ frame: EncodedAudioFrameInput) throws {
        guard isStarted else { throw AudioDecoderError.notStarted }
        guard !frame.data.isEmpty else { throw AudioDecoderError.invalidFrame }

        workerQueue.sync {
            let startTime = CFAbsoluteTimeGetCurrent()
            do {
                let converter = try ensureConverter()
                try performConversion(frame: frame, converter: converter, startTime: startTime)
            } catch {
                delegate?.audioDecoder(self, didFailWith: error)
            }
        }
    }

    // MARK: - Private Methods

    private func ensureConverter() throws -> AVAudioConverter {
        if let converter = self.converter {
            return converter
        }

        guard let configuration = self.configuration else {
            throw AudioDecoderError.notPrepared
        }

        // Create input format for Opus
        let inputSampleRate: Double = Double(configuration.codec.sampleRate ?? 48000)
        let inputChannels: UInt32 = configuration.codec.channelCount ?? 2

        var inputASBD = AudioStreamBasicDescription(
            mSampleRate: inputSampleRate,
            mFormatID: kAudioFormatOpus,
            mFormatFlags: 0,
            mBytesPerPacket: 0,  // Variable
            mFramesPerPacket: opusFrameSamples,  // 20ms @ 48kHz
            mBytesPerFrame: 0,  // Variable
            mChannelsPerFrame: inputChannels,
            mBitsPerChannel: 0,  // Variable
            mReserved: 0
        )

        guard let inputFormat = AVAudioFormat(streamDescription: &inputASBD) else {
            throw AudioDecoderError.unsupportedFormat
        }
        self.inputFormat = inputFormat

        // Create output format for PCM (48kHz, stereo, Float32)
        let outputSampleRate = configuration.outputSampleRate ?? 48000
        let outputChannels = configuration.outputChannelCount ?? 2

        guard let outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: outputSampleRate,
            channels: outputChannels
        ) else {
            throw AudioDecoderError.unsupportedFormat
        }
        self.outputFormat = outputFormat

        // Create converter
        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioDecoderError.converterCreationFailed
        }

        self.converter = converter
        logger.info("Created Opus decoder: Opus \(inputSampleRate)Hz \(inputChannels)ch -> PCM \(outputSampleRate)Hz \(outputChannels)ch")

        return converter
    }

    private func performConversion(frame: EncodedAudioFrameInput, converter: AVAudioConverter, startTime: CFAbsoluteTime) throws {
        guard let inputFormat = self.inputFormat,
              let outputFormat = self.outputFormat else {
            throw AudioDecoderError.notPrepared
        }

        // Create input buffer (compressed)
        // Opus typically produces 1 packet per 20ms frame
        let inputBuffer = AVAudioCompressedBuffer(format: inputFormat, packetCapacity: 1, maximumPacketSize: Int(frame.data.count))
        inputBuffer.byteLength = UInt32(frame.data.count)
        inputBuffer.packetCount = 1
        frame.data.copyBytes(to: inputBuffer.data.assumingMemoryBound(to: UInt8.self), count: frame.data.count)

        // Fill packet description
        if let packetDescriptions = inputBuffer.packetDescriptions {
            packetDescriptions[0] = AudioStreamPacketDescription(
                mStartOffset: 0,
                mVariableFramesInPacket: opusFrameSamples,
                mDataByteSize: UInt32(frame.data.count)
            )
        }

        // Calculate output frame count (same as input for same sample rate)
        let outputFrameCount = AVAudioFrameCount(Double(opusFrameSamples) * (outputFormat.sampleRate / inputFormat.sampleRate))

        // Create output buffer (PCM)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else {
            throw AudioDecoderError.internalError("Failed to create output buffer")
        }

        // Perform conversion
        var gotData = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { inNumPackets, outStatus in
            if gotData {
                outStatus.pointee = .noDataNow
                return nil
            }
            gotData = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let error = conversionError {
            throw AudioDecoderError.decodingFailed(error)
        }

        guard status != .error else {
            throw AudioDecoderError.internalError("Opus conversion returned error status")
        }

        guard outputBuffer.frameLength > 0 else {
            return
        }

        // Create decoded frame
        let pts = microsecondsToCMTime(frame.header.presentationTimestamp)
        let decodeTimeMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

        let decodedFrame = DecodedAudioFrame(
            pcmBuffer: outputBuffer,
            pts: pts,
            decodeTimeMs: decodeTimeMs
        )

        delegate?.audioDecoder(self, didDecode: decodedFrame)
    }

    private func microsecondsToCMTime(_ us: UInt64) -> CMTime {
        CMTimeMake(value: Int64(us), timescale: 1_000_000)
    }
}
