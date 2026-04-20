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

/// @unchecked Sendable: 모든 가변 상태 접근이 `workerQueue.sync` 로 직렬화된다.
final class VTVideoEncoder: NSObject, VideoEncoder, @unchecked Sendable {
    private let logger = SiriusLogger(category: "VTVideoEncoder")
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
    private var compressionSessionRefCon: UnsafeMutableRawPointer?
    
    fileprivate var shouldEmitParameterSets = true
    
    private var isStarted = false
    private var isVBRMode = false
    private var pendingForceKeyframe = false
    private var targetBitrateKbps: Int
    private var maxBitrateKbps: Int
    
    let events: AsyncStream<VideoEncoderEvent>
    fileprivate let continuation: AsyncStream<VideoEncoderEvent>.Continuation
    
    override init() {
        self.workerQueue = DispatchQueue(label: "app.noctiluca.server.projection.encoder.vt.worker", qos: .userInitiated)
        self.callbackQueue = DispatchQueue(label: "app.noctiluca.server.projection.encoder.vt.callback", qos: .userInitiated)
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
            releaseCompressionSessionRefConIfNeeded()
            isStarted = false
        }
        continuation.finish()
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
            if self.isVBRMode {
                if #available(macOS 26.0, *) {
                    success = self.applyVariableBitrate(bitrateKbps, to: session)
                }
            } else {
                success = self.applyAverageBitrate(bitrateKbps, to: session)
            }
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
            if self.isVBRMode {
                if #available(macOS 26.0, *) {
                    success = self.applyVBVMaxBitrate(bitrateKbps, to: session)
                }
            } else {
                success = self.applyMaxBitrate(bitrateKbps, to: session)
            }
        }
        return success
    }
    
    @discardableResult
    func updateExpectedFrameRate(_ fps: Float) -> Bool {
        var success = false
        workerQueue.sync {
            guard let session = self.compressionSession, fps > 0 else {
                success = false
                return
            }
            success = self.setProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate,
                                       value: NSNumber(value: fps))
        }
        return success
    }

}

// MARK: - Compression Session

private extension VTVideoEncoder {
    func releaseCompressionSessionRefConIfNeeded() {
        guard let refCon = compressionSessionRefCon else { return }
        Unmanaged<VTVideoEncoder>.fromOpaque(refCon).release()
        compressionSessionRefCon = nil
    }

    func ensureCompressionSession(for sampleBuffer: CMSampleBuffer) throws -> VTCompressionSession {
        if let session = compressionSession {
            return session
        }
        
        guard let configuration else { throw VideoEncoderError.notPrepared }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw VideoEncoderError.invalidSampleBuffer
        }
        let codec = configuration.codec
        
        let codecType = try codec.fourCC.codecType()
        let pixelBufferFormat = codec.cvPixelFormat
        
        let size = codec.size?.cgSize ??
            CGSize(width: CGFloat(CVPixelBufferGetWidth(imageBuffer)),
                   height: CGFloat(CVPixelBufferGetHeight(imageBuffer)))
        
        let sourceWidth = Int32(size.width)
        let sourceHeight = Int32(size.height)
        
        guard sourceWidth > 0, sourceHeight > 0 else {
            throw VideoEncoderError.invalidDimensions
        }
        
        var specification: [CFString: Any] = [:]
        
        let hardwareAccelOption = codec.option(.hardwareAcceleration)
        
        if hardwareAccelOption == .kHardwareAccelerationAuto {
            specification[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder] = true
        }
        
        /*
        else if hardwareAccelOption == .kHardwareAccelerationTrue {
            // requirement를 건다
            specification[kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder] = true
            specification[kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder] = true
        }
         */
        
        // specification[kVTVideoEncoderSpecification_EnableLowLatencyRateControl] = true
        
        var attributes: [CFString: Any] = [:]
        attributes[kCVPixelBufferPixelFormatTypeKey] = pixelBufferFormat
        
        
        var session: VTCompressionSession?
        let encoderRefCon = Unmanaged.passRetained(self)
        let refCon = UnsafeMutableRawPointer(encoderRefCon.toOpaque())
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: sourceWidth,
            height: sourceHeight,
            codecType: codecType,
            encoderSpecification: specification.isEmpty ? nil : specification as CFDictionary,
            imageBufferAttributes: attributes.isEmpty ? nil : attributes as CFDictionary,
            compressedDataAllocator: nil,
            outputCallback: compressionOutputCallback,
            refcon: refCon,
            compressionSessionOut: &session
        )
        
        guard status == noErr, let createdSession = session else {
            encoderRefCon.release()
            throw VideoEncoderError.compressionSessionFailed(status)
        }
        
        do {
            try applySessionProperties(createdSession)
        } catch {
            VTCompressionSessionInvalidate(createdSession)
            encoderRefCon.release()
            throw error
        }

        compressionSessionRefCon = refCon
        compressionSession = createdSession
        VTCompressionSessionPrepareToEncodeFrames(createdSession)
        return createdSession
    }
    
    func applySessionProperties(_ session: VTCompressionSession) throws {
        guard let configuration else { throw VideoEncoderError.notPrepared }
        
        let codec = configuration.codec

        setProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        setProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        
        // FIXME: 이거 제대로 된 값 설정해야됨
        setProperty(session, key: kVTCompressionPropertyKey_MaxAllowedFrameQP, value: 32 as CFNumber)
        
        // setProperty(session, key: kVTPixelTransferPropertyKey_ScalingMode, value: kVTScalingMode_Normal)
        
        /*
        */
        
        if false /* HDR not supported in MockServer */ {
            setProperty(session, key: kVTCompressionPropertyKey_ColorPrimaries, value: kCVImageBufferColorPrimaries_ITU_R_2020)
            setProperty(session, key: kVTCompressionPropertyKey_TransferFunction, value: kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ)
            setProperty(session, key: kVTCompressionPropertyKey_YCbCrMatrix, value: kCVImageBufferYCbCrMatrix_ITU_R_2020)
            
            setProperty(session, key: kVTCompressionPropertyKey_HDRMetadataInsertionMode, value: kVTHDRMetadataInsertionMode_Auto)
            setProperty(session, key: kVTCompressionPropertyKey_PreserveDynamicHDRMetadata, value: kCFBooleanTrue)
        }
        
        let frameRate = codec.frameRate ?? 0.0
        
        if frameRate > 0.0 {
            let rate = NSNumber(value: frameRate)
            setProperty(session, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: rate)
        }
        
        if let profileLevel = codec.profileLevelString {
            setProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: profileLevel)
        }
        
        // TODO: GOP 설정
        setProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, value: NSNumber(value: 4.0))
        
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
        /*
        if #available(macOS 26.0, *) {
            isVBRMode = true
            logger.info("Using VBR rate control mode")
            if targetBitrateKbps > 0 {
                applyVariableBitrate(targetBitrateKbps, to: session)
            }
            if maxBitrateKbps > 0 {
                applyVBVMaxBitrate(maxBitrateKbps, to: session)
            }
        } else {
            
        }
         */
        isVBRMode = false
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

private extension SiriusKit.Codec {
    var cvPixelFormat: OSType {
        let colorFormat = self.option(.colorFormat) ?? .kColorFormatYUV420
        let colorRange = self.option(.colorRange) ?? .kColorRangeLimited
        let supports10Bit = false
        
        
        if colorFormat == .kColorFormatYUV444 {
            if supports10Bit {
                return colorRange == .kColorRangeFull ?
                    kCVPixelFormatType_444YpCbCr10BiPlanarFullRange :
                    kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange
            } else {
                return colorRange == .kColorRangeFull ?
                    kCVPixelFormatType_444YpCbCr8BiPlanarFullRange :
                    kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange
            }
        } else {
            if supports10Bit {
                return colorRange == .kColorRangeFull ?
                    kCVPixelFormatType_420YpCbCr10BiPlanarFullRange :
                    kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            } else {
                return colorRange == .kColorRangeFull ?
                    kCVPixelFormatType_420YpCbCr8BiPlanarFullRange :
                    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            }
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
        let profile = self.option(.profile) ?? .kProfileAuto
        
        switch profile {
        case .kProfileH264High:
            return kVTProfileLevel_H264_High_AutoLevel
        case .kProfileH264Main:
            return kVTProfileLevel_H264_Main_AutoLevel
        case .kProfileH264Baseline:
            return kVTProfileLevel_H264_Baseline_AutoLevel
        case .kProfileAuto:
            fallthrough
        default:
            return nil
        }
    }
    
    func hevcProfileLevelString() -> CFString? {
        let profile = self.option(.profile) ?? .kProfileAuto
        
        switch profile {
        case .kProfileHEVCMain:
            return kVTProfileLevel_HEVC_Main_AutoLevel
        case .kProfileHEVCMain10:
            return kVTProfileLevel_HEVC_Main10_AutoLevel
        case .kProfileAuto:
            fallthrough
        default:
            return nil
        }
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
    // MARK: - ABR (Average Bit Rate) mode — macOS 10.8+

    @discardableResult
    func applyAverageBitrate(_ bitrateKbps: Int, to session: VTCompressionSession) -> Bool {
        let bitsPerSecond = bitrateBitsPerSecond(fromKbps: bitrateKbps)
        return setProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: NSNumber(value: bitsPerSecond))
    }

    @discardableResult
    func applyMaxBitrate(_ bitrateKbps: Int, to session: VTCompressionSession) -> Bool {
        let bytesPerSecond = bitrateBytesPerSecond(fromKbps: bitrateKbps)
        let limits: NSArray = [NSNumber(value: bytesPerSecond), NSNumber(value: 1.0)]
        return setProperty(session, key: kVTCompressionPropertyKey_DataRateLimits, value: limits)
    }

    // MARK: - VBR (Variable Bit Rate) mode — macOS 26.0+

    @available(macOS 26.0, *)
    @discardableResult
    func applyVariableBitrate(_ bitrateKbps: Int, to session: VTCompressionSession) -> Bool {
        let bitsPerSecond = bitrateBitsPerSecond(fromKbps: bitrateKbps)
        return setProperty(session, key: kVTCompressionPropertyKey_VariableBitRate, value: NSNumber(value: bitsPerSecond))
    }

    @available(macOS 26.0, *)
    @discardableResult
    func applyVBVMaxBitrate(_ bitrateKbps: Int, to session: VTCompressionSession) -> Bool {
        let bitsPerSecond = bitrateBitsPerSecond(fromKbps: bitrateKbps)
        return setProperty(session, key: kVTCompressionPropertyKey_VBVMaxBitRate, value: NSNumber(value: bitsPerSecond))
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
        encoder.continuation.yield(with: .success(.frameSkipped))
        return
    }
    
    var isKeyFrame = true
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]],
       let attachment = attachments.first,
       let notSync = attachment[kCMSampleAttachmentKey_NotSync] as? Bool {
        isKeyFrame = !notSync
    }

    // 키프레임마다 SPS/PPS를 재전송하여 첫 프레임 드랍 시에도 클라이언트가 디코더를 초기화할 수 있도록 함
    if isKeyFrame {
        encoder.shouldEmitParameterSets = true
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
        
        let parameterSetMessage = CodecParameterSetMessage(from: formatDescription, codec: configuration.codec.fourCC)
        
        encoder.continuation.yield(with: .success(.parameterSetChanged(
            consume parameterSetMessage
        )))
        
        encoder.shouldEmitParameterSets = false
    }
    
    encoder.continuation.yield(with: .success(.frameEncoded(consume encodedFrame)))
}
