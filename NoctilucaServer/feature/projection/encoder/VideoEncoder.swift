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
    let specification: CodecSpecification
    let desiredSize: CGSize?
    
    /// Optional source format description to seed the compression session.
    let inputFormatDescription: CMFormatDescription?
    
    init(specification: CodecSpecification, desiredSize: CGSize?, inputFormatDescription: CMFormatDescription?) {
        self.specification = specification
        self.desiredSize = desiredSize
        self.inputFormatDescription = inputFormatDescription
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
