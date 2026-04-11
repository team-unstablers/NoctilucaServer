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
import Accelerate // SIMD 및 고성능 연산을 위한 프레임워크

import SiriusKit

/// G.711 mu-law/A-law encoder.
/// Uses AVAudioConverter for resampling and a high-performance bit-pattern Lookup Table (LUT) for G.711 encoding.
///
/// @unchecked Sendable: 문서 Rule G 확장 (미디어 파이프라인 class 예외).
/// 가변 상태는 `workerQueue` 기반 직렬화와 AudioProjectionSession actor 경계에서 보호된다.
final class PCMAudioEncoder: NSObject, AudioEncoder, @unchecked Sendable {
    private let logger = NoctilucaLogger(category: "PCMAudioEncoder")
    private let workerQueue: DispatchQueue

    private var configuration: AudioEncoderConfiguration?
    
    // Resampler: Input -> 8kHz Mono LPCM (Int16)
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var intermediateFormat: AVAudioFormat? 

    private var isStarted = false
    private var frameCounter: UInt64 = 0

    let events: AsyncStream<AudioEncoderEvent>
    private let continuation: AsyncStream<AudioEncoderEvent>.Continuation

    override init() {
        self.workerQueue = DispatchQueue(label: "app.noctiluca.server.projection.encoder.pcm.worker", qos: .userInitiated)

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
        
        // Warm up LUT
        _ = G711LUT.shared
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
            self.intermediateFormat = nil
            self.isStarted = false
        }
        continuation.finish()
    }

    func flush() throws {}

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

        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPtr = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription) else {
            throw AudioEncoderError.invalidSampleBuffer
        }

        guard let inputFormat = AVAudioFormat(streamDescription: asbdPtr) else {
            throw AudioEncoderError.unsupportedFormat
        }
        self.inputFormat = inputFormat

        // Resample to 8kHz, 1ch, 16-bit LPCM
        guard let intermediateFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 8000, channels: 1, interleaved: true) else {
            throw AudioEncoderError.unsupportedFormat
        }
        self.intermediateFormat = intermediateFormat

        guard let converter = AVAudioConverter(from: inputFormat, to: intermediateFormat) else {
            throw AudioEncoderError.converterCreationFailed
        }

        self.converter = converter
        logger.info("Created G.711 Resampler: \(inputFormat.sampleRate)Hz -> 8000Hz LPCM")

        return converter
    }

    private func performConversion(sampleBuffer: CMSampleBuffer, converter: AVAudioConverter) throws {
        guard let inputFormat = self.inputFormat,
              let intermediateFormat = self.intermediateFormat,
              let configuration = self.configuration else {
            throw AudioEncoderError.notPrepared
        }

        guard let inputBuffer = createPCMBuffer(from: sampleBuffer, format: inputFormat) else {
            throw AudioEncoderError.invalidSampleBuffer
        }

        let ratio = intermediateFormat.sampleRate / inputFormat.sampleRate
        let outputFrameCount = AVAudioFrameCount(Double(inputBuffer.frameLength) * ratio)
        guard outputFrameCount > 0 else { return }

        guard let intermediateBuffer = AVAudioPCMBuffer(pcmFormat: intermediateFormat, frameCapacity: outputFrameCount) else {
            throw AudioEncoderError.internalError("Failed to create intermediate buffer")
        }

        var conversionError: NSError?
        let status = converter.convert(to: intermediateBuffer, error: &conversionError) { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let error = conversionError { throw AudioEncoderError.conversionFailed(error) }
        if status == .error { throw AudioEncoderError.internalError("Conversion failed") }

        // --- G.711 Encoding with LUT (SIMD-Friendly Loop) ---
        let codec = configuration.codec.fourCC
        let outputData = encodeG711(from: intermediateBuffer, codec: codec)

        guard !outputData.isEmpty else { return }

        // Create frame header & yield
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let header = FrameDataHeader(
            frameID: frameCounter,
            frameLength: UInt32(outputData.count),
            presentationTimestamp: microseconds(from: pts),
            flags: []
        )

        frameCounter += 1
        continuation.yield(.frameEncoded(EncodedAudioFrame(header: header, data: outputData)))
    }
    
    /// Encodes LPCM Int16 to G.711 using a bit-pattern optimized Lookup Table.
    private func encodeG711(from buffer: AVAudioPCMBuffer, codec: CodecFourCC) -> Data {
        guard let channelData = buffer.int16ChannelData?[0] else { return Data() }
        let count = Int(buffer.frameLength)
        
        var encoded = Data(count: count)
        let lut = (codec == .pcmu) ? G711LUT.shared.ulawTable : G711LUT.shared.alawTable
        
        encoded.withUnsafeMutableBytes { destPtr in
            guard let dest = destPtr.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            
            lut.withUnsafeBufferPointer { lutPtr in
                for i in 0..<count {
                    // Int16의 비트 패턴을 그대로 UInt16 인덱스로 사용 (연산량 0)
                    // 이 루프는 컴파일러에 의해 자동으로 Vectorization(SIMD)될 가능성이 매우 높습니다.
                    let idx = Int(UInt16(bitPattern: channelData[i]))
                    dest[i] = lutPtr[idx]
                }
            }
        }
        
        return encoded
    }

    private func createPCMBuffer(from sampleBuffer: CMSampleBuffer, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0, let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }

        var totalLength: Int = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
        
        guard status == kCMBlockBufferNoErr, let dataPointer = dataPointer else { return nil }

        if format.isInterleaved {
            memcpy(pcmBuffer.audioBufferList.pointee.mBuffers.mData, dataPointer, totalLength)
        } else {
            let channelCount = Int(format.channelCount)
            let bytesPerChannel = totalLength / channelCount
            for channel in 0..<channelCount {
                if let channelData = pcmBuffer.floatChannelData?[channel] {
                    memcpy(channelData, dataPointer.advanced(by: channel * bytesPerChannel), bytesPerChannel)
                }
            }
        }
        return pcmBuffer
    }

    private func microseconds(from time: CMTime) -> UInt64 {
        guard time.isValid, time.timescale != 0 else { return 0 }
        let scaled = CMTimeConvertScale(time, timescale: 1_000_000, method: .default)
        return scaled.value < 0 ? 0 : UInt64(scaled.value)
    }
}

// MARK: - G.711 Lookup Table (Bit-Pattern Optimized)
final class G711LUT: Sendable {
    static let shared = G711LUT()
    
    // Indices 0x0000...0xFFFF correspond directly to Int16 bit patterns.
    let ulawTable: [UInt8]
    let alawTable: [UInt8]
    
    private init() {
        var uTable = [UInt8](repeating: 0, count: 65536)
        var aTable = [UInt8](repeating: 0, count: 65536)
        
        for i in 0..<65536 {
            let pcm = Int16(bitPattern: UInt16(i))
            uTable[i] = G711Algorithm.linearToUlaw(pcm)
            aTable[i] = G711Algorithm.linearToAlaw(pcm)
        }
        
        self.ulawTable = uTable
        self.alawTable = aTable
    }
}

// MARK: - G.711 Algorithm (Private for LUT Generation)
fileprivate enum G711Algorithm {
    static func linearToUlaw(_ pcm: Int16) -> UInt8 {
        var p = Int(pcm) // Use Int to prevent overflow during negation of Int16.min
        let sign: UInt8 = (p < 0) ? 0x80 : 0x00
        if p < 0 { p = -p }
        if p > 32635 { p = 32635 }
        p += 0x84
        
        var exponent: UInt8 = 0
        if (p & 0x4000) != 0 { exponent = 7 }
        else if (p & 0x2000) != 0 { exponent = 6 }
        else if (p & 0x1000) != 0 { exponent = 5 }
        else if (p & 0x0800) != 0 { exponent = 4 }
        else if (p & 0x0400) != 0 { exponent = 3 }
        else if (p & 0x0200) != 0 { exponent = 2 }
        else if (p & 0x0100) != 0 { exponent = 1 }
        
        let mantissa = (p >> (exponent + 3)) & 0x0F
        return ~(sign | (exponent << 4) | UInt8(mantissa))
    }
    
    static func linearToAlaw(_ pcm: Int16) -> UInt8 {
        var p = Int(pcm) // Use Int to prevent overflow
        let mask: UInt8 = (p >= 0) ? 0xD5 : 0x55
        if p < 0 { p = -p - 8 }
        if p > 32767 { p = 32767 }
        
        var exponent: UInt8 = 0
        if (p & 0x4000) != 0 { exponent = 7 }
        else if (p & 0x2000) != 0 { exponent = 6 }
        else if (p & 0x1000) != 0 { exponent = 5 }
        else if (p & 0x0800) != 0 { exponent = 4 }
        else if (p & 0x0400) != 0 { exponent = 3 }
        else if (p & 0x0200) != 0 { exponent = 2 }
        else if (p & 0x0100) != 0 { exponent = 1 }
        
        let mantissa = (p >> (exponent == 0 ? 4 : exponent + 3)) & 0x0F
        return ((exponent << 4) | UInt8(mantissa)) ^ mask
    }
}

// MARK: - CodecFourCC Extension

extension CodecFourCC {
    static let pcmu = CodecFourCC("P", "C", "M", "U")
    static let pcma = CodecFourCC("P", "C", "M", "A")
    static let opus = CodecFourCC("O", "P", "U", "S")
}
