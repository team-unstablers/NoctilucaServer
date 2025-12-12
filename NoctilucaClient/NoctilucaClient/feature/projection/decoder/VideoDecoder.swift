import Foundation
import AVFoundation
import VideoToolbox
import SiriusKitClient

struct VideoDecoderConfiguration {
    let codec: Codec
    let parsedOptions: [String: String]
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
        self.parsedOptions = CodecOptionsParser.parse(optionsString: codec.options)
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

struct CodecOptionsParser {
    /// Parses an options string formatted as "key: 'value'; key2: 'value2'".
    static func parse(optionsString: String?) -> [String: String] {
        guard let optionsString, optionsString.isEmpty == false else { return [:] }
        
        let segments = optionsString.split(separator: ";")
        var parsed: [String: String] = [:]
        
        for segment in segments {
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { continue }
            
            let parts = trimmed.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            
            let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var value = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Only accept key: 'value' pattern.
            if value.hasPrefix("'"), value.hasSuffix("'"), value.count >= 2 {
                value.removeFirst()
                value.removeLast()
            } else {
                continue
            }
            
            parsed[key] = value
        }
        
        return parsed
    }
}
