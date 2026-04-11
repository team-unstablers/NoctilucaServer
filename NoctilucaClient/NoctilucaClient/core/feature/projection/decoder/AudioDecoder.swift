//
//  AudioDecoder.swift
//  NoctilucaClient
//
//  Created by Gyuhwan Park on 1/28/26.
//

import Foundation
import AVFoundation
import CoreMedia

import SiriusKitClient

/// Audio decoder configuration parameters.
struct AudioDecoderConfiguration: Sendable {
    /// Audio codec to use.
    let codec: SiriusKitClient.AudioCodec

    /// Output sample rate in Hz. If nil, uses default 48000 Hz.
    let outputSampleRate: Double?

    /// Output channel count. If nil, uses default 2 (stereo).
    let outputChannelCount: UInt32?

    init(
        codec: SiriusKitClient.AudioCodec,
        outputSampleRate: Double? = nil,
        outputChannelCount: UInt32? = nil
    ) {
        self.codec = codec
        self.outputSampleRate = outputSampleRate
        self.outputChannelCount = outputChannelCount
    }
}

/// Encoded audio frame input from the network.
struct EncodedAudioFrameInput: Sendable {
    let header: FrameDataHeader
    let data: Data
}

/// Decoded audio frame ready for playback.
///
/// `AVAudioPCMBuffer`는 공식적으로 `Sendable`로 선언되지 않았지만, 이 프레임은
/// 디코더 내부에서 생성된 후 jitter buffer / render callback 까지 한 방향으로만
/// 전달되고 생성 이후에는 불변으로 취급되므로, `@unchecked Sendable`로 처리한다.
struct DecodedAudioFrame: @unchecked Sendable {
    /// PCM buffer containing decoded audio samples.
    let pcmBuffer: AVAudioPCMBuffer

    /// Presentation timestamp.
    let pts: CMTime

    /// Time taken to decode this frame in milliseconds.
    let decodeTimeMs: Double
}

/// Delegate protocol for receiving decoded audio frames.
protocol AudioDecoderDelegate: AnyObject, Sendable {
    /// Called when an audio frame has been successfully decoded.
    func audioDecoder(_ decoder: AudioDecoder, didDecode frame: DecodedAudioFrame)

    /// Called when decoding fails.
    func audioDecoder(_ decoder: AudioDecoder, didFailWith error: Error)
}

/// Protocol defining the audio decoder interface.
protocol AudioDecoder: AnyObject, Sendable {
    /// Delegate to receive decoded frames and errors.
    var delegate: AudioDecoderDelegate? { get set }

    /// Prepares the decoder with the given configuration.
    /// - Parameter configuration: Decoder configuration including codec info.
    /// - Throws: `AudioDecoderError` if preparation fails.
    func prepare(with configuration: AudioDecoderConfiguration) throws

    /// Starts the decoder.
    /// - Throws: `AudioDecoderError` if the decoder is not prepared.
    func start() throws

    /// Decodes an encoded audio frame.
    /// - Parameter frame: The encoded audio frame input.
    /// - Throws: `AudioDecoderError` if decoding fails.
    func decode(_ frame: EncodedAudioFrameInput) throws

    /// Flushes any buffered data.
    /// - Throws: `AudioDecoderError` if flush fails.
    func flush() throws

    /// Stops the decoder and releases resources.
    /// - Throws: `AudioDecoderError` if stop fails.
    func stop() throws
}

/// Errors that can occur during audio decoding.
enum AudioDecoderError: LocalizedError {
    case notPrepared
    case alreadyPrepared
    case notStarted
    case unsupportedCodec(String)
    case invalidFrame
    case converterCreationFailed
    case decodingFailed(Error)
    case unsupportedFormat
    case internalError(String)

    var errorDescription: String? {
        switch self {
        case .notPrepared:
            return "AudioDecoder has not been prepared."
        case .alreadyPrepared:
            return "AudioDecoder has already been prepared."
        case .notStarted:
            return "AudioDecoder has not been started."
        case .unsupportedCodec(let fourCC):
            return "Unsupported audio codec: \(fourCC)"
        case .invalidFrame:
            return "Invalid audio frame data."
        case .converterCreationFailed:
            return "Failed to create audio converter."
        case .decodingFailed(let error):
            return "Audio decoding failed: \(error.localizedDescription)"
        case .unsupportedFormat:
            return "Unsupported audio format."
        case .internalError(let message):
            return "Internal error: \(message)"
        }
    }
}
