//
//  VideoEncoder.swift
//  MockServer
//
//  Copied from NoctilucaServer/feature/projection/encoder/VideoEncoder.swift
//

import Foundation
import AVFoundation
import VideoToolbox

import SiriusKit

struct VideoEncoderConfiguration {
    let codec: Codec
    let inputFormatDescription: CMFormatDescription?

    init(codec: Codec, inputFormatDescription: CMFormatDescription?) {
        self.codec = codec
        self.inputFormatDescription = inputFormatDescription
    }
}

struct EncodedFrame {
    let header: FrameDataHeader
    let data: Data
    let formatDescription: CMFormatDescription?
}

enum VideoEncoderEvent {
    case parameterSetChanged(CodecParameterSetMessage)
    case frameEncoded(EncodedFrame)
    case frameSkipped
    case errorOccurred(Error)
    case stopped
}

protocol VideoEncoderDelegate: AnyObject {
    func videoEncoder(_ encoder: VideoEncoder, didEncode frame: EncodedFrame)
    func videoEncoder(_ encoder: VideoEncoder, didFailWith error: Error)
}

protocol VideoEncoder: AnyObject {
    var events: AsyncStream<VideoEncoderEvent> { get }

    func prepare(with configuration: VideoEncoderConfiguration) throws
    func start() throws
    func encode(frameID: UInt64, sampleBuffer: CMSampleBuffer) throws
    func flush() throws
    func stop() throws

    func forceKeyframe()

    @discardableResult
    func updateTargetBitrate(_ bitrateKbps: Int) -> Bool

    @discardableResult
    func updateMaxBitrate(bitrateKbps: Int) -> Bool

    @discardableResult
    func updateQuality(_ quality: Float) -> Bool

    @discardableResult
    func updateQuantizeLevel(_ level: Int) -> Bool

    @discardableResult
    func updateExpectedFrameRate(_ fps: Float) -> Bool
}

extension VideoEncoder {
    func updateQuality(_ quality: Float) -> Bool { true }
    func updateQuantizeLevel(_ level: Int) -> Bool { false }
    func updateExpectedFrameRate(_ fps: Float) -> Bool { false }
}

enum VideoEncoderError: LocalizedError {
    case notPrepared
    case alreadyPrepared
    case notStarted
    case unsupportedCodec(String)
    case invalidDimensions
    case invalidSampleBuffer
    case compressionSessionFailed(OSStatus)
    case payloadTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .notPrepared:              return "VideoEncoder has not been prepared."
        case .alreadyPrepared:          return "VideoEncoder has already been prepared."
        case .notStarted:               return "VideoEncoder has not been started."
        case .unsupportedCodec(let f):  return "Unsupported codec FourCC: \(f)"
        case .invalidDimensions:        return "Invalid dimensions for compression session."
        case .invalidSampleBuffer:      return "Sample buffer is invalid."
        case .compressionSessionFailed(let s): return "Compression session failed with status: \(s)"
        case .payloadTooLarge(let l):   return "Encoded payload too large: \(l) bytes"
        }
    }
}
