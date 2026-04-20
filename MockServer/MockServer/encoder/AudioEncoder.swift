//
//  AudioEncoder.swift
//  MockServer
//
//  Copied from NoctilucaServer/feature/projection/encoder/AudioEncoder.swift
//

import Foundation
import AVFoundation
import CoreMedia

import SiriusKit

struct AudioEncoderConfiguration {
    let codec: SiriusKit.AudioCodec
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
    case frameEncoded(EncodedAudioFrame)
    case errorOccurred(any Error)
    case stopped
}

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
        case .notPrepared:              return "AudioEncoder has not been prepared."
        case .alreadyPrepared:          return "AudioEncoder has already been prepared."
        case .notStarted:               return "AudioEncoder has not been started."
        case .unsupportedCodec(let f):  return "Unsupported audio codec FourCC: \(f)"
        case .unsupportedFormat:        return "Unsupported audio format."
        case .invalidSampleBuffer:      return "Sample buffer is invalid."
        case .converterCreationFailed:  return "Failed to create audio converter."
        case .encodingFailed(let s):    return "Audio encoding failed with status: \(s)"
        case .conversionFailed(let e):  return "Audio conversion failed: \(e.localizedDescription)"
        case .payloadTooLarge(let l):   return "Encoded payload too large: \(l) bytes"
        case .internalError(let m):     return "Internal error: \(m)"
        }
    }
}
