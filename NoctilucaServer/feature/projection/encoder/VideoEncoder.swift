//
//  VideoEncoder.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Foundation
import AVFoundation
import VideoToolbox
import SiriusKit



struct VideoEncoderConfiguration {
    /// Sirius codec configuration from Projection channel.
    let codec: Codec
    /// Optional source format description to seed the compression session.
    let inputFormatDescription: CMFormatDescription?
    /// Parsed options from `codec.options`.
    let parsedOptions: [String: String]
    
    init(codec: Codec, inputFormatDescription: CMFormatDescription? = nil) {
        self.codec = codec
        self.inputFormatDescription = inputFormatDescription
        self.parsedOptions = CodecOptionsParser.parse(optionsString: codec.options)
    }
}

struct EncodedFrame {
    let header: FrameDataHeader
    let data: Data
    let formatDescription: CMFormatDescription?
}

protocol VideoEncoderDelegate: AnyObject {
    func videoEncoder(_ encoder: VideoEncoder, didEncode frame: EncodedFrame)
    func videoEncoder(_ encoder: VideoEncoder, didFailWith error: Error)
}

protocol VideoEncoder: AnyObject {
    var delegate: VideoEncoderDelegate? { get set }
    
    func prepare(with configuration: VideoEncoderConfiguration) throws
    func start() throws
    func encode(frameID: UInt64, sampleBuffer: CMSampleBuffer) throws
    func flush() throws
    func stop() throws
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
        case .notPrepared:
            return "VideoEncoder has not been prepared."
        case .alreadyPrepared:
            return "VideoEncoder has already been prepared."
        case .notStarted:
            return "VideoEncoder has not been started."
        case .unsupportedCodec(let fourCC):
            return "Unsupported codec FourCC: \(fourCC)"
        case .invalidDimensions:
            return "Invalid dimensions for compression session."
        case .invalidSampleBuffer:
            return "Sample buffer is invalid."
        case .compressionSessionFailed(let status):
            return "Compression session failed with status: \(status)"
        case .payloadTooLarge(let length):
            return "Encoded payload too large: \(length) bytes"
        }
    }
}

/*
enum CodecOptionKey: String {
    case colorFormat = "color-format"
    case hardwareAcceleration = "hardware-acceleration"
    case profile = "profile"
    case level = "level"
}
 */

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
