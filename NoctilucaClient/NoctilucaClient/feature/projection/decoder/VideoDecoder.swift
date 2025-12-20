import Foundation
import AVFoundation
import VideoToolbox
import SiriusKitClient

struct VideoDecoderConfiguration {
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

struct EncodedFrameInput {
    let header: FrameDataHeader
    let data: Data
    let formatDescription: CMFormatDescription?
}

struct DecodedFrame {
    let pixelBuffer: CVPixelBuffer
    let pts: CMTime
    let isKeyFrame: Bool
    let formatDescription: CMFormatDescription
    let decodeTimeMs: Double
}

protocol VideoDecoderDelegate: AnyObject {
    func videoDecoder(_ decoder: VideoDecoder, didDecode frame: DecodedFrame)
    func videoDecoder(_ decoder: VideoDecoder, didFailWith error: Error)
    func videoDecoder(_ decoder: VideoDecoder, didDropFrameWithID frameID: UInt64, reason: String)
}

protocol VideoDecoder: AnyObject {
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

enum CodecOptionKey: String {
    case colorFormat = "color-format"
    case hardwareAcceleration = "hardware-acceleration"
    case profile = "profile"
    case level = "level"
}

enum CodecColorFormat: String {
    case yuv420 = "yuv420"
    case yuv444 = "yuv444"
}

