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
    /// 코덱의 파라미터 세트(예: SPS, PPS 등)가 변경되었음을 알립니다.
    case parameterSetChanged(CodecParameterSetMessage)
    /// 프레임이 인코딩되어 준비되었음을 알립니다.
    case frameEncoded(EncodedFrame)
    
    /// 인코더가 프레임을 완성하지 못하고 건너뛴 경우를 알립니다.
    /// 서버 인코딩 성능 부족 시그널로 사용됩니다.
    case frameSkipped

    /// 인코딩 도중에 오류가 발생했음을 알립니다.
    case errorOccurred(Error)

    /// 인코더가 정지되었음을 알립니다.
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
    
    // MARK: - On-the-fly controls
    
    /// 다음에 입력으로 들어오는 프레임을 반드시 키프레임으로써 인코딩 해야 한다고 알립니다.
    /// NOTE: 이 요청은 곧바로 지켜지지 않을 수도 있습니다.
    func forceKeyframe()
    
    /// 인코딩 도중에 목표 비트레이트를 동적으로 변경합니다.
    /// NOTE: 이는 구현체에 따라, 옵션에 따라 곧바로 지켜지지 않을 수 있습니다.
    @discardableResult
    func updateTargetBitrate(_ bitrateKbps: Int) -> Bool
    
    /// 인코딩 도중에 최대 비트레이트를 동적으로 변경합니다.
    /// NOTE: 이는 구현체에 따라, 옵션에 따라 곧바로 지켜지지 않을 수 있습니다.
    @discardableResult
    func updateMaxBitrate(bitrateKbps: Int) -> Bool
    
    /// 인코딩 품질을 업데이트합니다 (0.0 = 최저 ~ 1.0 = 최고).
    /// 코덱에 따라 compressionLevel 등에 매핑됩니다.
    @discardableResult
    func updateQuality(_ quality: Float) -> Bool

    /// 양자화 레벨을 업데이트합니다 (0 = 없음 ~ 5 = 최대).
    @discardableResult
    func updateQuantizeLevel(_ level: Int) -> Bool

    /// 기대 프레임 레이트를 업데이트합니다.
    /// VT 인코더에서는 ExpectedFrameRate 힌트로 사용됩니다.
    @discardableResult
    func updateExpectedFrameRate(_ fps: Float) -> Bool

    /// 주어진 코덱 사양을 이 인코더가 처리할 수 있는지 확인합니다.
    static func isSupported(codec: CodecSpecification) -> Bool
}

extension VideoEncoder {
    static func isSupported(codec: CodecSpecification) -> Bool {
        return false
    }

    func updateQuality(_ quality: Float) -> Bool {
        return true
    }

    func updateQuantizeLevel(_ level: Int) -> Bool {
        return false
    }

    func updateExpectedFrameRate(_ fps: Float) -> Bool {
        return false
    }
}


enum VideoEncoderError: LocalizedError, Equatable {
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
