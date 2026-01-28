//
//  PCMAudioDecoder.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/28/26.
//

import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox

import SiriusKitClient

/// G.711 mu-law/A-law decoder using AVAudioConverter.
/// Performs resampling (8kHz -> 48kHz) and channel upmix (mono -> stereo).
final class PCMAudioDecoder: NSObject, AudioDecoder {
    private let logger = SiriusLogger(category: "PCMAudioDecoder", subsystem: "pl.unstabler.noctiluca.NoctilucaClient")
    private let workerQueue: DispatchQueue

    weak var delegate: AudioDecoderDelegate?

    private var configuration: AudioDecoderConfiguration?
    private var converter: AVAudioConverter?

    /// Input format: G.711 (8kHz, mono, 8-bit)
    private var inputFormat: AVAudioFormat?

    /// Output format: Linear PCM (48kHz, stereo, Float32)
    private var outputFormat: AVAudioFormat?

    private var isStarted = false

    override init() {
        self.workerQueue = DispatchQueue(label: "tech.unstablers.noctiluca.pcmaudiodecoder.worker")
        super.init()
    }

    func prepare(with configuration: AudioDecoderConfiguration) throws {
        guard self.configuration == nil else {
            throw AudioDecoderError.alreadyPrepared
        }

        let codec = configuration.codec
        let fourCC = codec.fourCC

        guard fourCC == .pcmu || fourCC == .pcma else {
            throw AudioDecoderError.unsupportedCodec(fourCC.stringRepresentation)
        }

        self.configuration = configuration
    }

    func start() throws {
        guard configuration != nil else {
            throw AudioDecoderError.notPrepared
        }
        isStarted = true
        logger.info("PCMAudioDecoder started")
    }

    func stop() throws {
        workerQueue.sync {
            self.converter = nil
            self.inputFormat = nil
            self.outputFormat = nil
            self.isStarted = false
        }
        logger.info("PCMAudioDecoder stopped")
    }

    func flush() throws {
        // G.711 has no internal buffering to flush
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

        // Create input format for G.711 (8kHz, mono)
        let formatID: AudioFormatID = configuration.codec.fourCC == .pcmu ? kAudioFormatULaw : kAudioFormatALaw
        let inputSampleRate: Double = Double(configuration.codec.sampleRate ?? 8000)
        let inputChannels: UInt32 = configuration.codec.channelCount ?? 1

        var inputASBD = AudioStreamBasicDescription(
            mSampleRate: inputSampleRate,
            mFormatID: formatID,
            mFormatFlags: 0,
            mBytesPerPacket: 1 * inputChannels,
            mFramesPerPacket: 1,
            mBytesPerFrame: 1 * inputChannels,
            mChannelsPerFrame: inputChannels,
            mBitsPerChannel: 8,
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
        logger.info("Created G.711 decoder: \(inputSampleRate)Hz \(inputChannels)ch -> \(outputSampleRate)Hz \(outputChannels)ch")

        return converter
    }

    private func performConversion(frame: EncodedAudioFrameInput, converter: AVAudioConverter, startTime: CFAbsoluteTime) throws {
        guard let inputFormat = self.inputFormat,
              let outputFormat = self.outputFormat else {
            throw AudioDecoderError.notPrepared
        }

        // Calculate frame counts
        let inputFrameCount = UInt32(frame.data.count) / UInt32(inputFormat.streamDescription.pointee.mBytesPerFrame)
        let outputFrameCount = AVAudioFrameCount(Double(inputFrameCount) * (outputFormat.sampleRate / inputFormat.sampleRate))

        guard inputFrameCount > 0, outputFrameCount > 0 else {
            return
        }

        // Create input buffer (compressed)
        let inputBuffer = AVAudioCompressedBuffer(format: inputFormat, packetCapacity: inputFrameCount, maximumPacketSize: 1)
        inputBuffer.byteLength = UInt32(frame.data.count)
        inputBuffer.packetCount = inputFrameCount
        frame.data.copyBytes(to: inputBuffer.data.assumingMemoryBound(to: UInt8.self), count: frame.data.count)

        // Fill packet descriptions (one packet per frame for G.711)
        if let packetDescriptions = inputBuffer.packetDescriptions {
            for i in 0..<Int(inputFrameCount) {
                packetDescriptions[i] = AudioStreamPacketDescription(
                    mStartOffset: Int64(i),
                    mVariableFramesInPacket: 0,
                    mDataByteSize: 1
                )
            }
        }

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
            throw AudioDecoderError.internalError("Conversion returned error status")
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
