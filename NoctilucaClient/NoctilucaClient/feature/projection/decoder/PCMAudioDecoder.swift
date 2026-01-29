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
import Accelerate

import SiriusKitClient

/// G.711 mu-law/A-law decoder.
/// Performs manual G.711 decoding to LPCM using LUT, then resamples using AVAudioConverter.
final class PCMAudioDecoder: NSObject, AudioDecoder {
    private let logger = SiriusLogger(category: "PCMAudioDecoder", subsystem: "pl.unstabler.noctiluca.NoctilucaClient")
    private let workerQueue: DispatchQueue

    weak var delegate: AudioDecoderDelegate?

    private var configuration: AudioDecoderConfiguration?
    private var converter: AVAudioConverter?

    /// Intermediate format: LPCM (8kHz, mono, 16-bit)
    private var intermediateFormat: AVAudioFormat?

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
        
        // Warm up LUT
        _ = G711DecoderLUT.shared
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
            self.intermediateFormat = nil
            self.outputFormat = nil
            self.isStarted = false
        }
        logger.info("PCMAudioDecoder stopped")
    }

    func flush() throws {}

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

        // 1. Create intermediate format: 8kHz, 1ch, 16-bit LPCM
        // We will decode G.711 to this format first.
        let inputSampleRate: Double = Double(configuration.codec.sampleRate ?? 8000)
        guard let intermediateFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: inputSampleRate, channels: 1, interleaved: true) else {
            throw AudioDecoderError.unsupportedFormat
        }
        self.intermediateFormat = intermediateFormat

        // 2. Create final output format (48kHz, stereo, Float32)
        let outputSampleRate = configuration.outputSampleRate ?? 48000
        let outputChannels = configuration.outputChannelCount ?? 2
        guard let outputFormat = AVAudioFormat(standardFormatWithSampleRate: outputSampleRate, channels: outputChannels) else {
            throw AudioDecoderError.unsupportedFormat
        }
        self.outputFormat = outputFormat

        // 3. Create converter from 8kHz LPCM to 48kHz Float32
        guard let converter = AVAudioConverter(from: intermediateFormat, to: outputFormat) else {
            throw AudioDecoderError.converterCreationFailed
        }

        self.converter = converter
        logger.info("Created G.711 decoder/resampler: G.711 -> \(inputSampleRate)Hz LPCM -> \(outputSampleRate)Hz \(outputChannels)ch")

        return converter
    }

    private func performConversion(frame: EncodedAudioFrameInput, converter: AVAudioConverter, startTime: CFAbsoluteTime) throws {
        guard let intermediateFormat = self.intermediateFormat,
              let outputFormat = self.outputFormat,
              let configuration = self.configuration else {
            throw AudioDecoderError.notPrepared
        }

        let inputFrameCount = frame.data.count // 1 byte per frame in G.711
        guard inputFrameCount > 0 else { return }

        // 1. Manually decode G.711 to Intermediate LPCM Buffer
        guard let intermediateBuffer = AVAudioPCMBuffer(pcmFormat: intermediateFormat, frameCapacity: AVAudioFrameCount(inputFrameCount)) else {
            throw AudioDecoderError.internalError("Failed to create intermediate buffer")
        }
        
        let codec = configuration.codec.fourCC
        decodeG711(from: frame.data, to: intermediateBuffer, codec: codec)
        intermediateBuffer.frameLength = AVAudioFrameCount(inputFrameCount)

        // 2. Resample LPCM to Final Output Buffer
        let ratio = outputFormat.sampleRate / intermediateFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(inputFrameCount) * ratio)
        
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputFrameCount) else {
            throw AudioDecoderError.internalError("Failed to create output buffer")
        }

        var gotData = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if gotData {
                outStatus.pointee = .noDataNow
                return nil
            }
            gotData = true
            outStatus.pointee = .haveData
            return intermediateBuffer
        }

        if let error = conversionError { throw AudioDecoderError.decodingFailed(error) }
        if status == .error { throw AudioDecoderError.internalError("Conversion failed") }

        if outputBuffer.frameLength > 0 {
            let pts = microsecondsToCMTime(frame.header.presentationTimestamp)
            let decodeTimeMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000

            delegate?.audioDecoder(self, didDecode: DecodedAudioFrame(
                pcmBuffer: outputBuffer,
                pts: pts,
                decodeTimeMs: decodeTimeMs
            ))
        }
    }
    
    private func decodeG711(from data: Data, to buffer: AVAudioPCMBuffer, codec: CodecFourCC) {
        guard let dest = buffer.int16ChannelData?[0] else { return }
        let lut = (codec == .pcmu) ? G711DecoderLUT.shared.ulawTable : G711DecoderLUT.shared.alawTable
        
        data.withUnsafeBytes { srcPtr in
            guard let src = srcPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            
            lut.withUnsafeBufferPointer { lutPtr in
                for i in 0..<data.count {
                    dest[i] = lutPtr[Int(src[i])]
                }
            }
        }
    }

    private func microsecondsToCMTime(_ us: UInt64) -> CMTime {
        CMTimeMake(value: Int64(us), timescale: 1_000_000)
    }
}

// MARK: - G.711 Decoder Lookup Table
final class G711DecoderLUT {
    static let shared = G711DecoderLUT()
    
    let ulawTable: [Int16]
    let alawTable: [Int16]
    
    private init() {
        var uTable = [Int16](repeating: 0, count: 256)
        var aTable = [Int16](repeating: 0, count: 256)
        
        for i in 0..<256 {
            let byte = UInt8(i)
            uTable[i] = G711Algorithm.ulawToLinear(byte)
            aTable[i] = G711Algorithm.alawToLinear(byte)
        }
        
        self.ulawTable = uTable
        self.alawTable = aTable
    }
}

// MARK: - G.711 Algorithm (Private for LUT Generation)
fileprivate enum G711Algorithm {
    static func ulawToLinear(_ ulaw: UInt8) -> Int16 {
        let u = Int(~ulaw)
        let sign = (u & 0x80) != 0
        let exponent = (u >> 4) & 0x07
        let mantissa = u & 0x0F
        var sample = (mantissa << 3) + 0x84
        sample <<= exponent
        sample -= 0x84
        return Int16(sign ? -sample : sample)
    }
    
    static func alawToLinear(_ alaw: UInt8) -> Int16 {
        var a = Int(alaw ^ 0xD5)
        let sign = (a & 0x80) != 0
        let exponent = (a >> 4) & 0x07
        let mantissa = a & 0x0F
        var sample = (mantissa << 4) + (exponent == 0 ? 8 : 0x108)
        if exponent > 1 {
            sample <<= (exponent - 1)
        }
        return Int16(sign ? -sample : sample)
    }
}