//
//  AudioEncoder.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 1/28/26.
//

import Foundation
import AVFoundation
import CoreMedia

import SiriusKit

struct AudioEncoderConfiguration {
    /// Sirius codec configuration from Projection channel.
    let codec: SiriusKit.AudioCodec

    /// Optional source format description to seed the encoder.
    let inputFormatDescription: CMAudioFormatDescription?

    init(codec: SiriusKit.AudioCodec, inputFormatDescription: CMAudioFormatDescription?) {
        self.codec = codec
        self.inputFormatDescription = inputFormatDescription
    }
}

struct EncodedAudioFrame: Sendable {
    let header: FrameDataHeader
    let data: Data
}

enum AudioEncoderEvent: Sendable {
    /// 프레임이 인코딩되어 준비되었음을 알립니다.
    case frameEncoded(EncodedAudioFrame)

    /// 인코딩 도중에 오류가 발생했음을 알립니다.
    case errorOccurred(any Error)

    /// 인코더가 정지되었음을 알립니다.
    case stopped
}

/// NOTE: 본체 프로토콜에 Sendable 표식 필요. 사유는 `VideoEncoder` 주석 참조.
protocol AudioEncoder: AnyObject, Sendable {
    var events: AsyncStream<AudioEncoderEvent> { get }

    func prepare(with configuration: AudioEncoderConfiguration) throws
    func start() throws
    func encode(sampleBuffer: CMSampleBuffer) throws
    func flush() throws
    func stop() throws
}

enum AudioEncoderError: LocalizedError {
    case notPrepared
    case alreadyPrepared
    case notStarted
    case unsupportedCodec(String)
    case unsupportedFormat
    case invalidSampleBuffer
    case converterCreationFailed
    case encodingFailed(OSStatus)
    case conversionFailed(Error)
    case payloadTooLarge(Int)
    case internalError(String)

    var errorDescription: String? {
        switch self {
        case .notPrepared:
            return "AudioEncoder has not been prepared."
        case .alreadyPrepared:
            return "AudioEncoder has already been prepared."
        case .notStarted:
            return "AudioEncoder has not been started."
        case .unsupportedCodec(let fourCC):
            return "Unsupported audio codec FourCC: \(fourCC)"
        case .unsupportedFormat:
            return "Unsupported audio format."
        case .invalidSampleBuffer:
            return "Sample buffer is invalid."
        case .converterCreationFailed:
            return "Failed to create audio converter."
        case .encodingFailed(let status):
            return "Audio encoding failed with status: \(status)"
        case .conversionFailed(let error):
            return "Audio conversion failed: \(error.localizedDescription)"
        case .payloadTooLarge(let length):
            return "Encoded payload too large: \(length) bytes"
        case .internalError(let message):
            return "Internal error: \(message)"
        }
    }
}
