import Foundation
import AVFoundation
import VideoToolbox
import SiriusKit

private final class FrameEncodeContext {
    let frameID: UInt64
    let pts: CMTime
    
    init(frameID: UInt64, pts: CMTime) {
        self.frameID = frameID
        self.pts = pts
    }
}

final class VTVideoEncoder: NSObject, VideoEncoder {
    weak var delegate: VideoEncoderDelegate?
    
    private let logger = NoctilucaLogger(category: "VTVideoEncoder")
    private let workerQueue: DispatchQueue
    internal let callbackQueue: DispatchQueue
    
    private var configuration: VideoEncoderConfiguration?
    private var compressionSession: VTCompressionSession?
    private var isStarted = false
    
    override init() {
        self.workerQueue = DispatchQueue(label: "tech.unstablers.noctiluca.vtencoder.worker")
        self.callbackQueue = DispatchQueue(label: "tech.unstablers.noctiluca.vtencoder.callback")
        super.init()
    }
    
    init(workerQueue: DispatchQueue, callbackQueue: DispatchQueue) {
        self.workerQueue = workerQueue
        self.callbackQueue = callbackQueue
        super.init()
    }
    
    func prepare(with configuration: VideoEncoderConfiguration) throws {
        guard self.configuration == nil else {
            throw VideoEncoderError.alreadyPrepared
        }
        self.configuration = configuration
    }
    
    func start() throws {
        guard configuration != nil else {
            throw VideoEncoderError.notPrepared
        }
        isStarted = true
    }
    
    func stop() throws {
        workerQueue.sync {
            if let session = compressionSession {
                VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
                VTCompressionSessionInvalidate(session)
            }
            compressionSession = nil
            isStarted = false
        }
    }
    
    func flush() throws {
        guard let session = compressionSession else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
    }
    
    func encode(frameID: UInt64, sampleBuffer: CMSampleBuffer) throws {
        guard isStarted else { throw VideoEncoderError.notStarted }
        guard CMSampleBufferDataIsReady(sampleBuffer) else { throw VideoEncoderError.invalidSampleBuffer }
        
        try workerQueue.sync {
            let session = try ensureCompressionSession(for: sampleBuffer)
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                throw VideoEncoderError.invalidSampleBuffer
            }
            
            let context = FrameEncodeContext(frameID: frameID, pts: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            let unmanagedContext = Unmanaged.passRetained(context)
            
            var infoFlags = VTEncodeInfoFlags()
            let status = VTCompressionSessionEncodeFrame(
                session,
                imageBuffer: imageBuffer,
                presentationTimeStamp: context.pts,
                duration: .invalid,
                frameProperties: nil,
                sourceFrameRefcon: unmanagedContext.toOpaque(),
                infoFlagsOut: &infoFlags
            )
            
            if status != noErr {
                unmanagedContext.release()
                throw VideoEncoderError.compressionSessionFailed(status)
            }
        }
    }
}

// MARK: - Compression Session

private extension VTVideoEncoder {
    func ensureCompressionSession(for sampleBuffer: CMSampleBuffer) throws -> VTCompressionSession {
        if let session = compressionSession {
            return session
        }
        
        guard let configuration else { throw VideoEncoderError.notPrepared }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw VideoEncoderError.invalidSampleBuffer
        }
        
        let (codecType, fourCCString) = try codecType(for: configuration.codec)
        let pixelBufferFormat = requestedPixelFormat(from: configuration.parsedOptions)
        let sourceWidth = configuration.codec.width.map { Int32($0) } ?? Int32(CVPixelBufferGetWidth(imageBuffer))
        let sourceHeight = configuration.codec.height.map { Int32($0) } ?? Int32(CVPixelBufferGetHeight(imageBuffer))
        
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw VideoEncoderError.invalidDimensions
        }
        
        var specification: [CFString: Any] = [:]
        if let hwAccel = hardwareAcceleration(from: configuration.parsedOptions) {
            specification[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder] = hwAccel
            specification[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder] = hwAccel
        }
        
        var attributes: [CFString: Any] = [:]
        if let pixelFormat = pixelBufferFormat {
            attributes[kCVPixelBufferPixelFormatTypeKey] = pixelFormat
        }
        
        var session: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: sourceWidth,
            height: sourceHeight,
            codecType: codecType,
            encoderSpecification: specification.isEmpty ? nil : specification as CFDictionary,
            imageBufferAttributes: attributes.isEmpty ? nil : attributes as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: compressionOutputCallback,
            refcon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            compressionSessionOut: &session
        )
        
        guard status == noErr, let createdSession = session else {
            throw VideoEncoderError.compressionSessionFailed(status)
        }
        
        applySessionProperties(createdSession, codec: configuration.codec, parsedOptions: configuration.parsedOptions, codecString: fourCCString)
        compressionSession = createdSession
        VTCompressionSessionPrepareToEncodeFrames(createdSession)
        return createdSession
    }
    
    func applySessionProperties(_ session: VTCompressionSession, codec: Codec, parsedOptions: [String: String], codecString: String) {
        setProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        setProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        
        if let frameRate = codec.frameRate, frameRate > 0 {
            let rate = NSNumber(value: frameRate)
            setProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: rate)
        }
        
        if let profileLevel = profileLevelString(for: codec, parsedOptions: parsedOptions) {
            setProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: profileLevel)
        }
        
        if let colorFormat = colorFormat(from: parsedOptions) {
            // Best effort: request higher chroma resolution; actual support depends on hardware.
            switch colorFormat {
            case .yuv444:
                setProperty(session, key: kVTCompressionPropertyKey_AllowOpenGOP, value: kCFBooleanFalse)
            case .yuv420:
                break
            }
        }
        
        applyQualitySettings(session, codec: codec, codecString: codecString)
    }
    
    func applyQualitySettings(_ session: VTCompressionSession, codec: Codec, codecString: String) {
        switch codec.quality {
        case .constantBitrate(let quality):
            let bitrate = max(Int(quality.bitrateKbps), 0) * 1000
            if bitrate > 0 {
                setProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrate))
                setProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: [NSNumber(value: bitrate), NSNumber(value: 1)] as NSArray)
            }
            
        case .variableBitrate(let quality):
            let target = max(Int(quality.targetBitrateKbps), 0) * 1000
            let maxRate = max(Int(quality.maxBitrateKbps), 0) * 1000
            if target > 0 {
                setProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: target))
            }
            if maxRate > 0 {
                setProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: [NSNumber(value: maxRate), NSNumber(value: 1)] as NSArray)
            }
            
        case .fixedQuality(let quality):
            let clamped = max(0, min(Int(quality.quality), 100))
            let vtQuality = Float(1.0 - (Float(clamped) / 100.0))
            setProperty(session, key: kVTCompressionPropertyKey_Quality, value: NSNumber(value: vtQuality))
            
        case .lossless(_):
            setProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
            setProperty(session, key: kVTCompressionPropertyKey_AllowOpenGOP, value: kCFBooleanFalse)
            setProperty(session, key: kVTCompressionPropertyKey_Quality, value: NSNumber(value: 1.0))
            
        case .auto(_), .none:
            logger.info("Using default quality settings for codec: \(codecString)")
        }
    }
}

// MARK: - Helpers

private extension VTVideoEncoder {
    func codecType(for codec: Codec) throws -> (CMVideoCodecType, String) {
        let fourCCValue = codec.fourCC.bigEndian
        let chars: [UInt8] = [
            UInt8((fourCCValue >> 24) & 0xFF),
            UInt8((fourCCValue >> 16) & 0xFF),
            UInt8((fourCCValue >> 8) & 0xFF),
            UInt8(fourCCValue & 0xFF),
        ]
        
        let fourCCString = String(bytes: chars, encoding: .ascii)?.uppercased() ?? ""
        switch fourCCString {
        case "AVC1":
            return (kCMVideoCodecType_H264, fourCCString)
        case "HVC1":
            return (kCMVideoCodecType_HEVC, fourCCString)
        default:
            throw VideoEncoderError.unsupportedCodec(fourCCString)
        }
    }
    
    func requestedPixelFormat(from options: [String: String]) -> OSType? {
        guard let formatValue = options[CodecOptionKey.colorFormat.rawValue]?.lowercased() else {
            return nil
        }
        
        switch formatValue {
        case CodecColorFormat.yuv444.rawValue:
            return kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange
        case CodecColorFormat.yuv420.rawValue:
            fallthrough
        default:
            return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        }
    }
    
    func colorFormat(from options: [String: String]) -> CodecColorFormat? {
        guard let value = options[CodecOptionKey.colorFormat.rawValue]?.lowercased() else { return nil }
        return CodecColorFormat(rawValue: value)
    }
    
    func hardwareAcceleration(from options: [String: String]) -> Bool? {
        guard let value = options[CodecOptionKey.hardwareAcceleration.rawValue]?.lowercased() else {
            return nil
        }
        switch value {
        case "true":
            return true
        case "false":
            return false
        default:
            return nil
        }
    }
    
    func profileLevelString(for codec: Codec, parsedOptions: [String: String]) -> CFString? {
        guard let profile = parsedOptions[CodecOptionKey.profile.rawValue]?.lowercased() else {
            return nil
        }
        
        let levelString = parsedOptions[CodecOptionKey.level.rawValue]
        let normalizedLevel = levelString?.replacingOccurrences(of: ".", with: "_")
        
        let fourCCValue = codec.fourCC.bigEndian
        let chars: [UInt8] = [
            UInt8((fourCCValue >> 24) & 0xFF),
            UInt8((fourCCValue >> 16) & 0xFF),
            UInt8((fourCCValue >> 8) & 0xFF),
            UInt8(fourCCValue & 0xFF),
        ]
        let fourCCString = String(bytes: chars, encoding: .ascii)?.uppercased() ?? ""
        
        let levelComponent = normalizedLevel.map { "Level\($0)" } ?? "AutoLevel"
        switch fourCCString {
        case "AVC1":
            let prefix: String
            switch profile {
            case "baseline": prefix = "H264_Baseline"
            case "main": prefix = "H264_Main"
            case "high": prefix = "H264_High"
            default: return nil
            }
            return "\(prefix)_\(levelComponent)" as CFString
            
        case "HVC1":
            let prefix: String
            switch profile {
            case "main": prefix = "HEVC_Main"
            case "main10": prefix = "HEVC_Main10"
            case "mainstill", "mainstillpicture": prefix = "HEVC_MainStillPicture"
            default: return nil
            }
            return "\(prefix)_\(levelComponent)" as CFString
            
        default:
            return nil
        }
    }
    
    func setProperty(_ session: VTCompressionSession, key: CFString, value: CFTypeRef) {
        let status = VTSessionSetProperty(session, key: key, value: value)
        if status != noErr {
            logger.error("Failed to set property \(key) status=\(status)")
        }
    }
    
    func microseconds(from time: CMTime) -> UInt64 {
        guard time.isValid, time.timescale != 0 else { return 0 }
        let scaled = CMTimeConvertScale(time, timescale: 1_000_000, method: .default)
        if scaled.value < 0 {
            return 0
        }
        return UInt64(scaled.value)
    }
}

// MARK: - Output Callback

private func compressionOutputCallback(
    outputCallbackRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTEncodeInfoFlags,
    sampleBuffer: CMSampleBuffer?
) {
    guard
        let refCon = outputCallbackRefCon,
        let encoder = Unmanaged<VTVideoEncoder>.fromOpaque(refCon).takeUnretainedValue() as VTVideoEncoder?
    else {
        return
    }
    
    guard let sourceFrameRefCon else { return }
    let context = Unmanaged<FrameEncodeContext>.fromOpaque(sourceFrameRefCon).takeRetainedValue()
    
    if status != noErr {
        encoder.callbackQueue.async {
            encoder.delegate?.videoEncoder(encoder, didFailWith: VideoEncoderError.compressionSessionFailed(status))
        }
        return
    }
    
    guard let sampleBuffer = sampleBuffer, CMSampleBufferDataIsReady(sampleBuffer) else {
        encoder.callbackQueue.async {
            encoder.delegate?.videoEncoder(encoder, didFailWith: VideoEncoderError.invalidSampleBuffer)
        }
        return
    }
    
    var isKeyFrame = true
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
       let attachment = attachments.first,
       let notSync = attachment[kCMSampleAttachmentKey_NotSync] as? Bool {
        isKeyFrame = !notSync
    }
    
    guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
        encoder.callbackQueue.async {
            encoder.delegate?.videoEncoder(encoder, didFailWith: VideoEncoderError.invalidSampleBuffer)
        }
        return
    }
    
    var lengthAtOffset: Int = 0
    var totalLength: Int = 0
    var dataPointer: UnsafeMutablePointer<Int8>?
    let statusCode = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
    
    guard statusCode == kCMBlockBufferNoErr, let dataPointer else {
        encoder.callbackQueue.async {
            encoder.delegate?.videoEncoder(encoder, didFailWith: VideoEncoderError.invalidSampleBuffer)
        }
        return
    }
    
    let data = Data(bytes: dataPointer, count: totalLength)
    guard data.count <= Int(UInt32.max) else {
        encoder.callbackQueue.async {
            encoder.delegate?.videoEncoder(encoder, didFailWith: VideoEncoderError.payloadTooLarge(data.count))
        }
        return
    }
    
    let header = FrameDataHeader(
        frameID: context.frameID,
        frameLength: UInt32(data.count),
        presentationTimestamp: encoder.microseconds(from: context.pts),
        isKeyFrame: isKeyFrame
    )
    
    let encodedFrame = EncodedFrame(
        header: header,
        data: data,
        formatDescription: CMSampleBufferGetFormatDescription(sampleBuffer)
    )
    
    encoder.callbackQueue.async {
        encoder.delegate?.videoEncoder(encoder, didEncode: encodedFrame)
    }
}
