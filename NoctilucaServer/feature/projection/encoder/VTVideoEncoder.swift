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
    private let logger = NoctilucaLogger(category: "VTVideoEncoder")
    private let workerQueue: DispatchQueue
    internal let callbackQueue: DispatchQueue
    private let defaultTargetBitrateKbps = 1200
    private let defaultMaxBitrateKbps = 2400
    
    fileprivate var configuration: VideoEncoderConfiguration?
    private var compressionSession: VTCompressionSession? {
        didSet {
            // 인코더 세션이 새로 만들어지면 parameter sets를 다시 보내야 한다.
            self.shouldEmitParameterSets = true
        }
    }
    
    fileprivate var shouldEmitParameterSets = true
    
    private var isStarted = false
    private var pendingForceKeyframe = false
    private var targetBitrateKbps: Int
    private var maxBitrateKbps: Int
    
    let events: AsyncStream<VideoEncoderEvent>
    fileprivate let continuation: AsyncStream<VideoEncoderEvent>.Continuation
    
    override init() {
        self.workerQueue = DispatchQueue(label: "tech.unstablers.noctiluca.vtencoder.worker")
        self.callbackQueue = DispatchQueue(label: "tech.unstablers.noctiluca.vtencoder.callback")
        self.targetBitrateKbps = defaultTargetBitrateKbps
        self.maxBitrateKbps = defaultMaxBitrateKbps
        
        var continuationLocal: AsyncStream<VideoEncoderEvent>.Continuation!
        
        self.events = AsyncStream<VideoEncoderEvent>(VideoEncoderEvent.self, bufferingPolicy: .unbounded) { continuation in
            continuationLocal = continuation
        }
        
        self.continuation = continuationLocal
        
        super.init()
    }
    
    init(workerQueue: DispatchQueue, callbackQueue: DispatchQueue) {
        self.workerQueue = workerQueue
        self.callbackQueue = callbackQueue
        self.targetBitrateKbps = defaultTargetBitrateKbps
        self.maxBitrateKbps = defaultMaxBitrateKbps
        
        var continuationLocal: AsyncStream<VideoEncoderEvent>.Continuation!
        
        self.events = AsyncStream<VideoEncoderEvent>(VideoEncoderEvent.self, bufferingPolicy: .unbounded) { continuation in
            continuationLocal = continuation
        }
        
        self.continuation = continuationLocal
        
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
            
            let shouldForceKeyframe = pendingForceKeyframe
            pendingForceKeyframe = false
            let frameProperties: CFDictionary?
            if shouldForceKeyframe {
                frameProperties = [kVTEncodeFrameOptionKey_ForceKeyFrame as String: true] as CFDictionary
            } else {
                frameProperties = nil
            }
            
            let context = FrameEncodeContext(frameID: frameID, pts: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
            let unmanagedContext = Unmanaged.passRetained(context)
            
            var infoFlags = VTEncodeInfoFlags()
            let status = VTCompressionSessionEncodeFrame(
                session,
                imageBuffer: imageBuffer,
                presentationTimeStamp: context.pts,
                duration: .invalid,
                frameProperties: frameProperties,
                sourceFrameRefcon: unmanagedContext.toOpaque(),
                infoFlagsOut: &infoFlags
            )
            
            if status != noErr {
                if shouldForceKeyframe {
                    pendingForceKeyframe = true
                }
                unmanagedContext.release()
                throw VideoEncoderError.compressionSessionFailed(status)
            }
        }
    }
    
    // MARK: - On-the-fly controls
    
    func forceKeyframe() {
        workerQueue.async {
            self.pendingForceKeyframe = true
        }
    }
    
    @discardableResult
    func updateTargetBitrate(_ bitrateKbps: Int) -> Bool {
        var success = false
        workerQueue.sync {
            guard bitrateKbps > 0 else {
                self.logger.error("Target bitrate must be positive (kbps=\(bitrateKbps))")
                success = false
                return
            }
            self.targetBitrateKbps = bitrateKbps
            guard let session = self.compressionSession else {
                success = true
                return
            }
            success = self.applyAverageBitrate(bitrateKbps, to: session)
        }
        return success
    }
    
    @discardableResult
    func updateMaxBitrate(bitrateKbps: Int) -> Bool {
        var success = false
        workerQueue.sync {
            guard bitrateKbps > 0 else {
                self.logger.error("Max bitrate must be positive (kbps=\(bitrateKbps))")
                success = false
                return
            }
            self.maxBitrateKbps = bitrateKbps
            guard let session = self.compressionSession else {
                success = true
                return
            }
            success = self.applyMaxBitrate(bitrateKbps, to: session)
        }
        return success
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
        let codecSpecification = configuration.specification
        
        let codecType = try codecSpecification.fourCC.codecType()
        let pixelBufferFormat = codecSpecification.cvPixelFormat
        
        let size = configuration.desiredSize ??
            CGSize(width: CGFloat(CVPixelBufferGetWidth(imageBuffer)),
                   height: CGFloat(CVPixelBufferGetHeight(imageBuffer)))
        
        let sourceWidth = Int32(size.width)
        let sourceHeight = Int32(size.height)
        
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw VideoEncoderError.invalidDimensions
        }
        
        var specification: [CFString: Any] = [:]
        
        let hardwareAccelOption = codecSpecification.options[.hardwareAcceleration]
        
        if hardwareAccelOption == .kHardwareAccelerationTrue {
            specification[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder] = true
        } else if hardwareAccelOption == .kHardwareAccelerationForced {
            // requirement를 건다
            specification[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder] = true
            specification[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder] = true
        }
        
        // specification[kVTVideoEncoderSpecification_EnableLowLatencyRateControl] = true
        
        var attributes: [CFString: Any] = [:]
        attributes[kCVPixelBufferPixelFormatTypeKey] = pixelBufferFormat
        attributes[kCVImageBufferYCbCrMatrixKey] = kCVImageBufferYCbCrMatrix_ITU_R_2020
        
        
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
        
        try applySessionProperties(createdSession)
        compressionSession = createdSession
        VTCompressionSessionPrepareToEncodeFrames(createdSession)
        return createdSession
    }
    
    func applySessionProperties(_ session: VTCompressionSession) throws {
        guard let configuration else { throw VideoEncoderError.notPrepared }
        
        let codecSpecification = configuration.specification

        setProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        setProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        
        // setProperty(session, key: kVTPixelTransferPropertyKey_ScalingMode, value: kVTScalingMode_Normal)
        
        /*
        setProperty(session, key: kVTCompressionPropertyKey_HDRMetadataInsertionMode, value: kVTHDRMetadataInsertionMode_Auto)
        setProperty(session, key: kVTCompressionPropertyKey_PreserveDynamicHDRMetadata, value: kCFBooleanTrue)
        */
         
        setProperty(session, key: kVTCompressionPropertyKey_ColorPrimaries, value: kCVImageBufferColorPrimaries_ITU_R_2020)
        setProperty(session, key: kVTCompressionPropertyKey_TransferFunction, value: kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ)
        setProperty(session, key: kVTCompressionPropertyKey_YCbCrMatrix, value: kCVImageBufferYCbCrMatrix_ITU_R_2020)
        

        
        if codecSpecification.frameRate > 0 {
            let rate = NSNumber(value: codecSpecification.frameRate)
            setProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: rate)
        }
        
        if let profileLevel = codecSpecification.profileLevelString {
            setProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: profileLevel)
        }
        
        // TODO: GOP 설정
        
        /*
        if let colorFormat = colorFormat(from: parsedOptions) {
            // Best effort: request higher chroma resolution; actual support depends on hardware.
            switch colorFormat {
            case .yuv444:
                setProperty(session, key: kVTCompressionPropertyKey_AllowOpenGOP, value: kCFBooleanFalse)
            case .yuv420:
                break
            }
        }
         */
        
        try applyQualitySettings(session)
    }
    
    func applyQualitySettings(_ session: VTCompressionSession) throws {
        if targetBitrateKbps > 0 {
            applyAverageBitrate(targetBitrateKbps, to: session)
        }
        
        if maxBitrateKbps > 0 {
            applyMaxBitrate(maxBitrateKbps, to: session)
        }

        /*
        switch codec.quality {
        case .constantBitrate(let bitrateKbps):
            let bitrate = max(Int(bitrateKbps), 0) * 1000
            if bitrate > 0 {
                setProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitrate))
                setProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: [NSNumber(value: bitrate), NSNumber(value: 1)] as NSArray)
            }
            
        case .variableBitrate(let targetBitrateKbps, let maxBitrateKbps):
            let target = max(Int(targetBitrateKbps), 0) * 1000
            let maxRate = max(Int(maxBitrateKbps), 0) * 1000
            if target > 0 {
                setProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: target))
            }
            if maxRate > 0 {
                setProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: [NSNumber(value: maxRate), NSNumber(value: 1)] as NSArray)
            }
            
        case .fixedQuality(let factor):
            let clamped = max(0, min(Int(factor), 100))
            let vtQuality = Float(1.0 - (Float(clamped) / 100.0))
            setProperty(session, key: kVTCompressionPropertyKey_Quality, value: NSNumber(value: vtQuality))
            
        case .lossless(_):
            setProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
            setProperty(session, key: kVTCompressionPropertyKey_AllowOpenGOP, value: kCFBooleanFalse)
            setProperty(session, key: kVTCompressionPropertyKey_Quality, value: NSNumber(value: 1.0))
            
        case .auto(_):
            logger.info("Using default quality settings for codec: \(codecString)")
        }
         */
    }
}

// MARK: - Helpers

private extension CodecFourCC {
    func codecType() throws -> CMVideoCodecType {
        switch self {
        case .avc1:
            return kCMVideoCodecType_H264
        case .hvc1:
            return kCMVideoCodecType_HEVC
        default:
            throw VideoEncoderError.unsupportedCodec(self.stringRepresentation)
        }
    }
}

private extension CodecSpecification {
    var cvPixelFormat: OSType {
        let colorFormat = self.options[.colorFormat] ?? .kColorFormatYUV420
        
        switch colorFormat {
        case .kColorFormatYUV444:
            return kCVPixelFormatType_444YpCbCr10BiPlanarFullRange

            
        case .kColorFormatAuto:
            fallthrough
        case .kColorFormatYUV420:
            fallthrough
        default:
            return kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        }
    }
    
    var profileLevelString: CFString? {
        switch self.fourCC {
        case .avc1:
            return h264ProfileLevelString()
        case .hvc1:
            return hevcProfileLevelString()
        default:
            return nil
        }
    }
    
    func h264ProfileLevelString() -> CFString? {
        let level = "AutoLevel"
        
        let profile = options[.profile] ?? .kProfileAuto
        
        switch profile {
        case .kProfileH264High:
            return "H264_High_\(level)" as CFString
        case .kProfileH264Main:
            return "H264_Main_\(level)" as CFString
        case .kProfileH264Baseline:
            return "H264_Baseline_\(level)" as CFString
        case .kProfileAuto:
            fallthrough
        default:
            return nil
        }
    }
    
    func hevcProfileLevelString() -> CFString? {
        /*
            let prefix: String
            switch profile {
            case "main": prefix = "HEVC_Main"
            case "main10": prefix = "HEVC_Main10"
            case "mainstill", "mainstillpicture": prefix = "HEVC_MainStillPicture"
            default: return nil
            }
            return "\(prefix)_\(levelComponent)" as CFString
         */
        let level = "AutoLevel"
        
        let profile = options[.profile] ?? .kProfileAuto
        
        // return "HEVC_Main_\(level)" as CFString
        return kVTProfileLevel_HEVC_Main10_AutoLevel
    }
}

private extension CodecParameterSetMessage {
    init(from formatDescription: CMFormatDescription, codec: CodecFourCC) {
        let parameterSets: [CodecParameterSet] = switch codec {
        case .avc1:
            Self.extractH264ParameterSets(formatDescription)
        case .hvc1:
            Self.extractHEVCParameterSets(formatDescription)
        default:
            []
        }
        
        self.init(parameterSets: consume parameterSets)
    }
    
    static func extractH264ParameterSets(_ formatDescription: CMFormatDescription) -> [CodecParameterSet] {
        formatDescription.parameterSets.compactMap { parameterSetData in
            let naluTypeByte = parameterSetData[0] & 0x1F
            
            switch naluTypeByte {
            case 7:
                // SPS
                return CodecParameterSet(type: .avc1SPS, data: parameterSetData)
            case 8:
                // PPS
                return CodecParameterSet(type: .avc1PPS, data: parameterSetData)
            default:
                return nil
            }
        }
    }
    
    static func extractHEVCParameterSets(_ formatDescription: CMFormatDescription) -> [CodecParameterSet] {
        formatDescription.parameterSets.compactMap { parameterSetData in
            let naluTypeByte = (parameterSetData[0] >> 1) & 0x3F
            
            switch naluTypeByte {
            case 32:
                // VPS
                return CodecParameterSet(type: .hvc1VPS, data: parameterSetData)
            case 33:
                // SPS
                return CodecParameterSet(type: .hvc1SPS, data: parameterSetData)
            case 34:
                // PPS
                return CodecParameterSet(type: .hvc1PPS, data: parameterSetData)
            default:
                return nil
            }
        }
    }
}

private extension VTVideoEncoder {
    @discardableResult
    func applyAverageBitrate(_ bitrateKbps: Int, to session: VTCompressionSession) -> Bool {
        let bitsPerSecond = bitrateBitsPerSecond(fromKbps: bitrateKbps)
        return setProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitsPerSecond))
    }
    
    @discardableResult
    func applyMaxBitrate(_ bitrateKbps: Int, to session: VTCompressionSession) -> Bool {
        let bytesPerSecond = bitrateBytesPerSecond(fromKbps: bitrateKbps)
        let limits: NSArray = [NSNumber(value: bytesPerSecond), NSNumber(value: 1)]
        return setProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: limits)
    }
    
    func bitrateBitsPerSecond(fromKbps bitrateKbps: Int) -> Int {
        return max(bitrateKbps, 0) * 1000
    }
    
    func bitrateBytesPerSecond(fromKbps bitrateKbps: Int) -> Int {
        return bitrateBitsPerSecond(fromKbps: bitrateKbps) / 8
    }
    
    @discardableResult
    func setProperty(_ session: VTCompressionSession, key: CFString, value: CFTypeRef) -> Bool {
        let status = VTSessionSetProperty(session, key: key, value: value)
        if status != noErr {
            logger.error("Failed to set property \(key) status=\(status)")
            return false
        }
        return true
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
        encoder.continuation.yield(with: .success(.errorOccurred(
            VideoEncoderError.compressionSessionFailed(status)
        )))
        return
    }
    
    guard let sampleBuffer = sampleBuffer, CMSampleBufferDataIsReady(sampleBuffer) else {
        encoder.continuation.yield(with: .success(.errorOccurred(
            VideoEncoderError.invalidSampleBuffer
        )))
        return
    }
    
    var isKeyFrame = true
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
       let attachment = attachments.first,
       let notSync = attachment[kCMSampleAttachmentKey_NotSync] as? Bool {
        isKeyFrame = !notSync
    }
    
    guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
        encoder.continuation.yield(with: .success(.errorOccurred(
            VideoEncoderError.invalidSampleBuffer
        )))
        return
    }
    
    var lengthAtOffset: Int = 0
    var totalLength: Int = 0
    var dataPointer: UnsafeMutablePointer<Int8>?
    let statusCode = CMBlockBufferGetDataPointer(dataBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
    
    guard statusCode == kCMBlockBufferNoErr, let dataPointer else {
        encoder.continuation.yield(with: .success(.errorOccurred(
            VideoEncoderError.invalidSampleBuffer
        )))
        return
    }
    
    let data = Data(bytes: dataPointer, count: totalLength)
    guard data.count <= Int(UInt32.max) else {
        encoder.continuation.yield(with: .success(.errorOccurred(
            VideoEncoderError.payloadTooLarge(data.count)
        )))
        return
    }
    
    let header = FrameDataHeader(
        frameID: context.frameID,
        frameLength: UInt32(data.count),
        presentationTimestamp: encoder.microseconds(from: context.pts),
        flags: [.isKeyframe]
    )
    
    let encodedFrame = EncodedFrame(
        header: header,
        data: data,
        formatDescription: nil
    )
    
    if encoder.shouldEmitParameterSets {
        assert(encoder.configuration != nil, "configuration must be set if parameter sets are to be emitted")
        
        let configuration = encoder.configuration!
        let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)!
        
        let parameterSetMessage = CodecParameterSetMessage(from: formatDescription, codec: configuration.specification.fourCC)
        
        encoder.continuation.yield(with: .success(.parameterSetChanged(
            consume parameterSetMessage
        )))
        
        encoder.shouldEmitParameterSets = false
    }
    
    encoder.continuation.yield(with: .success(.frameEncoded(consume encodedFrame)))
}

