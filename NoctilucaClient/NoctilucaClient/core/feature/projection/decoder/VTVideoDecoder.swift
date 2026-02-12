import Foundation
import AVFoundation
import VideoToolbox
import SiriusKitClient

/// `paramErr` (-50) is not available on iOS (Carbon/MacTypes.h is macOS-only).
private let kParamErr: OSStatus = -50

enum VTDecompressionBackend: Equatable {
    case hardware
    case software
}

struct VTDecompressionSessionCreationAttempt: Equatable {
    let requiresHardwareDecoder: Bool
    let backend: VTDecompressionBackend
}

private final class FrameDecodeContext {
    let header: FrameDataHeader
    let pts: CMTime
    let formatDescription: CMFormatDescription
    let decodeStart: DispatchTime
    
    init(header: FrameDataHeader, pts: CMTime, formatDescription: CMFormatDescription, decodeStart: DispatchTime) {
        self.header = header
        self.pts = pts
        self.formatDescription = formatDescription
        self.decodeStart = decodeStart
    }
}

final class VTVideoDecoder: NSObject, VideoDecoder {
    typealias DecompressionSessionCreateHandler = (
        CMFormatDescription,
        CFDictionary?,
        CFDictionary?,
        UnsafeMutablePointer<VTDecompressionOutputCallbackRecord>,
        UnsafeMutablePointer<VTDecompressionSession?>
    ) -> OSStatus

    static var decompressionSessionCreationAttempts: [VTDecompressionSessionCreationAttempt] {
#if targetEnvironment(simulator)
        return [
            VTDecompressionSessionCreationAttempt(
                requiresHardwareDecoder: false,
                backend: .software
            ),
        ]
#else
        return [
            VTDecompressionSessionCreationAttempt(
                requiresHardwareDecoder: true,
                backend: .hardware
            ),
            VTDecompressionSessionCreationAttempt(
                requiresHardwareDecoder: false,
                backend: .software
            ),
        ]
#endif
    }

    weak var delegate: VideoDecoderDelegate?
    
    private let logger = NoctilucaLogger(category: "VTVideoDecoder", subsystem: "projection.decoder")
    private let workerQueue: DispatchQueue
    internal let callbackQueue: DispatchQueue
    private let decompressionSessionCreateHandler: DecompressionSessionCreateHandler
    
    private var configuration: VideoDecoderConfiguration?
    private var decompressionSession: VTDecompressionSession?
    internal var currentFormatDescription: CMFormatDescription?
    private var isStarted = false
    private(set) var activeBackend: VTDecompressionBackend?

    var decoderTypeName: String {
        switch activeBackend {
        case .hardware:
            return "VideoToolbox (HW)"
        case .software:
            return "VideoToolbox (SW)"
        case .none:
            return "VideoToolbox"
        }
    }
    
    override init() {
        self.workerQueue = DispatchQueue(label: NoctilucaMeta.scopedIdentifier("projection.decoder.VTVideoDecoder.workerQueue"), qos: .userInitiated)
        self.callbackQueue = DispatchQueue(label: NoctilucaMeta.scopedIdentifier("projection.decoder.VTVideoDecoder.callbackQueue"), qos: .userInitiated)
        self.decompressionSessionCreateHandler = VTVideoDecoder.defaultDecompressionSessionCreateHandler
        super.init()
    }
    
    init(
        workerQueue: DispatchQueue,
        callbackQueue: DispatchQueue,
        decompressionSessionCreateHandler: @escaping DecompressionSessionCreateHandler =
            VTVideoDecoder.defaultDecompressionSessionCreateHandler
    ) {
        self.workerQueue = workerQueue
        self.callbackQueue = callbackQueue
        self.decompressionSessionCreateHandler = decompressionSessionCreateHandler
        super.init()
    }

    deinit {
        workerQueue.sync {
            if let session = decompressionSession {
                VTDecompressionSessionFinishDelayedFrames(session)
                VTDecompressionSessionInvalidate(session)
            }
            decompressionSession = nil
            currentFormatDescription = nil
            activeBackend = nil
        }
    }

    func prepare(with configuration: VideoDecoderConfiguration) throws {
        guard self.configuration == nil else {
            throw VideoDecoderError.alreadyPrepared
        }
        self.configuration = configuration
    }
    
    func start() throws {
        guard configuration != nil else {
            throw VideoDecoderError.notPrepared
        }
        isStarted = true
    }
    
    func stop() throws {
        workerQueue.sync {
            if let session = decompressionSession {
                VTDecompressionSessionFinishDelayedFrames(session)
                VTDecompressionSessionInvalidate(session)
            }
            decompressionSession = nil
            currentFormatDescription = nil
            activeBackend = nil
            isStarted = false
        }
    }
    
    func flush() throws {
        guard let session = decompressionSession else { return }
        VTDecompressionSessionFinishDelayedFrames(session)
    }
    
    func decode(_ frame: EncodedFrameInput) throws {
        guard isStarted else { throw VideoDecoderError.notStarted }
        let expectedLength = Int(frame.header.frameLength)
        guard expectedLength == frame.data.count else {
            throw VideoDecoderError.payloadLengthMismatch(expected: expectedLength, actual: frame.data.count)
        }
        
        try workerQueue.sync {
            let session = try ensureDecompressionSession(using: frame)
            let sampleBuffer = try makeSampleBuffer(from: frame)
            
            let formatDescription = currentFormatDescription ?? frame.formatDescription
            guard let formatDescription else {
                throw VideoDecoderError.invalidFormatDescription
            }
            
            let context = FrameDecodeContext(
                header: frame.header,
                pts: pts(fromMicroseconds: frame.header.presentationTimestamp),
                formatDescription: formatDescription,
                decodeStart: DispatchTime.now()
            )
            
            var infoFlags = VTDecodeInfoFlags()
            let unmanagedContext = Unmanaged.passRetained(context)
            let status = VTDecompressionSessionDecodeFrame(
                session,
                sampleBuffer: sampleBuffer,
                flags: [],
                frameRefcon: unmanagedContext.toOpaque(),
                infoFlagsOut: &infoFlags
            )
            
            if status != noErr {
                unmanagedContext.release()
                throw VideoDecoderError.decompressionSessionFailed(status)
            }
        }
    }
}

// MARK: - Session setup

private extension VTVideoDecoder {
    static func defaultDecompressionSessionCreateHandler(
        formatDescription: CMFormatDescription,
        decoderSpecification: CFDictionary?,
        imageBufferAttributes: CFDictionary?,
        outputCallback: UnsafeMutablePointer<VTDecompressionOutputCallbackRecord>,
        decompressionSessionOut: UnsafeMutablePointer<VTDecompressionSession?>
    ) -> OSStatus {
        VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: decoderSpecification,
            imageBufferAttributes: imageBufferAttributes,
            outputCallback: outputCallback,
            decompressionSessionOut: decompressionSessionOut
        )
    }

    func ensureDecompressionSession(using frame: EncodedFrameInput) throws -> VTDecompressionSession {
        if let session = decompressionSession {
            return session
        }
        
        guard let configuration else { throw VideoDecoderError.notPrepared }
        
        let formatDescription = frame.formatDescription ?? configuration.initialFormatDescription
        guard let formatDescription else {
            throw VideoDecoderError.invalidFormatDescription
        }
        
        let codec = configuration.codec

        var attributes: [CFString: Any] = [:]
        attributes[kCVPixelBufferPixelFormatTypeKey] = codec.cvPixelFormat

        var callbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionOutputCallback,
            decompressionOutputRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )

        let attributeDictionary = attributes.isEmpty ? nil : attributes as CFDictionary
        var lastStatus: OSStatus = kParamErr

        for (index, attempt) in Self.decompressionSessionCreationAttempts.enumerated() {
            let specification = decoderSpecification(for: attempt)
            var session: VTDecompressionSession?
            let status = decompressionSessionCreateHandler(
                formatDescription,
                specification,
                attributeDictionary,
                &callbackRecord,
                &session
            )

            guard status == noErr, let createdSession = session else {
                let normalizedStatus = status == noErr ? kParamErr : status
                lastStatus = normalizedStatus

                if index + 1 < Self.decompressionSessionCreationAttempts.count {
                    let message = """
                    Failed to create VT decompression session \
                    (backend=\(attempt.backend.logLabel), status=\(normalizedStatus)). \
                    Trying fallback backend.
                    """
                    logger.warning(
                        message
                    )
                } else {
                    let message = """
                    Failed to create VT decompression session \
                    (backend=\(attempt.backend.logLabel), status=\(normalizedStatus)).
                    """
                    logger.error(
                        message
                    )
                }
                continue
            }

            VTSessionSetProperty(
                createdSession,
                key: kVTDecompressionPropertyKey_GeneratePerFrameHDRDisplayMetadata,
                value: kCFBooleanTrue
            )
            decompressionSession = createdSession
            currentFormatDescription = formatDescription
            activeBackend = attempt.backend
            let message = """
            Created decompression session for codec: \(codec.fourCC.stringRepresentation), \
            backend=\(attempt.backend.logLabel)
            """
            logger.info(
                message
            )

            return createdSession
        }

        throw VideoDecoderError.decompressionSessionFailed(lastStatus)
    }

    func decoderSpecification(for attempt: VTDecompressionSessionCreationAttempt) -> CFDictionary? {
        guard attempt.requiresHardwareDecoder else {
            return nil
        }

        let specification: [CFString: Any] = [
            kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder: kCFBooleanTrue as Any,
        ]
        return specification as CFDictionary
    }
    
    func makeSampleBuffer(from frame: EncodedFrameInput) throws -> CMSampleBuffer {
        let pts = pts(fromMicroseconds: frame.header.presentationTimestamp)
        guard let formatDescription = currentFormatDescription ?? frame.formatDescription else {
            throw VideoDecoderError.invalidFormatDescription
        }
        
        var blockBuffer: CMBlockBuffer?
        let status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: frame.data.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: frame.data.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        
        guard status == kCMBlockBufferNoErr, let blockBuffer else {
            throw VideoDecoderError.invalidBitstream
        }
        
        let replaceStatus = frame.data.withUnsafeBytes { bytes -> OSStatus in
            guard let baseAddress = bytes.baseAddress else { return kCMBlockBufferBadCustomBlockSourceErr }
            return CMBlockBufferReplaceDataBytes(
                with: baseAddress,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: frame.data.count
            )
        }
        
        guard replaceStatus == kCMBlockBufferNoErr else {
            throw VideoDecoderError.invalidBitstream
        }
        
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        
        var sampleBuffer: CMSampleBuffer?
        let sizes = [frame.data.count]
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: sizes,
            sampleBufferOut: &sampleBuffer
        )
        
        guard sampleStatus == noErr, let sampleBuffer else {
            throw VideoDecoderError.invalidBitstream
        }
        
        return sampleBuffer
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
            throw VideoDecoderError.unsupportedCodec(self.stringRepresentation)
        }
    }
}

private extension SiriusKitClient.Codec {
    var cvPixelFormat: OSType {
        let colorFormat = self.option(.colorFormat) ?? .kColorFormatYUV420
        let colorRange = self.option(.colorRange) ?? .kColorRangeLimited
        let supports10Bit = self.supports10Bit
        
        
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

private extension VTVideoDecoder {
    func pts(fromMicroseconds value: UInt64) -> CMTime {
        CMTime(value: CMTimeValue(value), timescale: 1_000_000)
    }
}

private extension VTDecompressionBackend {
    var logLabel: String {
        switch self {
        case .hardware:
            return "hardware"
        case .software:
            return "software"
        }
    }
}

// MARK: - Output callback

private func decompressionOutputCallback(
    decompressionOutputRefCon: UnsafeMutableRawPointer?,
    sourceFrameRefCon: UnsafeMutableRawPointer?,
    status: OSStatus,
    infoFlags: VTDecodeInfoFlags,
    imageBuffer: CVImageBuffer?,
    presentationTimeStamp: CMTime,
    presentationDuration: CMTime
) {
    guard
        let refCon = decompressionOutputRefCon,
        let decoder = Unmanaged<VTVideoDecoder>.fromOpaque(refCon).takeUnretainedValue() as VTVideoDecoder?
    else {
        return
    }
    
    guard let sourceFrameRefCon else { return }
    let context = Unmanaged<FrameDecodeContext>.fromOpaque(sourceFrameRefCon).takeRetainedValue()
    
    if status != noErr {
        decoder.callbackQueue.async {
            decoder.delegate?.videoDecoder(decoder, didFailWith: VideoDecoderError.decompressionSessionFailed(status))
        }
        return
    }
    
    guard let pixelBuffer = imageBuffer else {
        decoder.callbackQueue.async {
            decoder.delegate?.videoDecoder(decoder, didFailWith: VideoDecoderError.invalidBitstream)
        }
        return
    }
    
    let formatDescription = decoder.currentFormatDescription ?? context.formatDescription
    let decodeEnd = DispatchTime.now()
    let decodeMs = max(0, Double(decodeEnd.uptimeNanoseconds - context.decodeStart.uptimeNanoseconds) / 1_000_000.0)
    let decodedFrame = DecodedFrame(
        pixelBuffer: pixelBuffer,
        pts: context.pts,
        isKeyFrame: context.header.flags.contains(.isKeyframe),
        formatDescription: formatDescription,
        decodeTimeMs: decodeMs
    )
    
    decoder.callbackQueue.async {
        decoder.delegate?.videoDecoder(decoder, didDecode: decodedFrame)
    }
}
