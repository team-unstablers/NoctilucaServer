import Foundation
@preconcurrency import AVFoundation
@preconcurrency import VideoToolbox

import SiriusKitClient

struct VideoDecoderConfiguration: Sendable {
    let codec: Codec
    let preferredOutputPixelFormat: OSType?
    let initialFormatDescription: CMFormatDescription?

    init(
        codec: Codec,
        preferredOutputPixelFormat: OSType? = nil,
        initialFormatDescription: CMFormatDescription? = nil
    ) {
        self.codec = codec
        self.preferredOutputPixelFormat = preferredOutputPixelFormat
        self.initialFormatDescription = initialFormatDescription
    }
}

struct EncodedFrameInput: Sendable {
    let header: FrameDataHeader
    let data: Data
    let formatDescription: CMFormatDescription?
}

struct DecodedFrame: Sendable {
    let pixelBuffer: CVPixelBuffer
    let pts: CMTime
    let isKeyFrame: Bool
    let formatDescription: CMFormatDescription
    let decodeTimeMs: Double
}

protocol VideoDecoderDelegate: AnyObject, Sendable {
    func videoDecoder(_ decoder: VideoDecoder, didDecode frame: DecodedFrame)
    func videoDecoder(_ decoder: VideoDecoder, didFailWith error: Error)
    func videoDecoder(_ decoder: VideoDecoder, didDropFrameWithID frameID: UInt64, reason: String)
}

protocol VideoDecoder: AnyObject, Sendable {
    var delegate: VideoDecoderDelegate? { get set }

    func prepare(with configuration: VideoDecoderConfiguration) throws
    func start() throws
    func decode(_ frame: EncodedFrameInput) throws
    func flush() throws
    func stop() throws
}

enum VideoDecoderError: LocalizedError {
    case notPrepared
    case alreadyPrepared
    case notStarted
    case unsupportedCodec(String)
    case invalidFormatDescription
    case invalidBitstream
    case payloadLengthMismatch(expected: Int, actual: Int)
    case decompressionSessionFailed(OSStatus)
    
    var errorDescription: String? {
        switch self {
        case .notPrepared:
            return "VideoDecoder has not been prepared."
        case .alreadyPrepared:
            return "VideoDecoder has already been prepared."
        case .notStarted:
            return "VideoDecoder has not been started."
        case .unsupportedCodec(let fourCC):
            return "Unsupported codec FourCC: \(fourCC)"
        case .invalidFormatDescription:
            return "Invalid or missing format description."
        case .invalidBitstream:
            return "Invalid bitstream."
        case .payloadLengthMismatch(let expected, let actual):
            return "Payload length mismatch. expected=\(expected) actual=\(actual)"
        case .decompressionSessionFailed(let status):
            return "Decompression session failed with status: \(status)"
        }
    }
}
