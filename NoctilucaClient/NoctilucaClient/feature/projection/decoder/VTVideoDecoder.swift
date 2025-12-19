import Foundation
import AVFoundation
import VideoToolbox
import SiriusKitClient

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
    weak var delegate: VideoDecoderDelegate?
    
    private let logger = NoctilucaLogger(category: "VTVideoDecoder", subsystem: "projection.decoder")
    private let workerQueue: DispatchQueue
    internal let callbackQueue: DispatchQueue
    
    private var configuration: VideoDecoderConfiguration?
    private var decompressionSession: VTDecompressionSession?
    internal var currentFormatDescription: CMFormatDescription?
    private var isStarted = false
    
    override init() {
        self.workerQueue = DispatchQueue(label: NoctilucaMeta.scopedIdentifier("projection.decoder.VTVideoDecoder.workerQueue"))
        self.callbackQueue = DispatchQueue(label: NoctilucaMeta.scopedIdentifier("projection.decoder.VTVideoDecoder.callbackQueue"))
        super.init()
    }
    
    init(workerQueue: DispatchQueue, callbackQueue: DispatchQueue) {
        self.workerQueue = workerQueue
        self.callbackQueue = callbackQueue
        super.init()
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
    func ensureDecompressionSession(using frame: EncodedFrameInput) throws -> VTDecompressionSession {
        if let session = decompressionSession {
            return session
        }
        
        guard let configuration else { throw VideoDecoderError.notPrepared }
        
        let formatDescription = frame.formatDescription ?? configuration.initialFormatDescription
        guard let formatDescription else {
            throw VideoDecoderError.invalidFormatDescription
        }
        
        let (_, fourCCString) = try codecType(for: configuration.codec)
        
        var specification: [CFString: Any] = [:]
#if !targetEnvironment(simulator)
        if let hw = hardwareAcceleration(from: configuration.parsedOptions) {
            // FIXME: 이거 해보고 실패하면 소프트웨어 디코드로 fallback하는거 있어야 함
            
            specification[kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder] = hw
            // specification[kVTVideoDecoderSpecification_AllowHardwareAcceleratedVideoDecoder] = hw
        }
#endif
        
        var attributes: [CFString: Any] = [:]
        if let pixelFormat = requestedPixelFormat(from: configuration.parsedOptions, preferred: configuration.preferredOutputPixelFormat) {
            attributes[kCVPixelBufferPixelFormatTypeKey] = pixelFormat
        }
        
        var callbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decompressionOutputCallback,
            decompressionOutputRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        
        var session: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: formatDescription,
            decoderSpecification: specification.isEmpty ? nil : specification as CFDictionary,
            imageBufferAttributes: attributes.isEmpty ? nil : attributes as CFDictionary,
            outputCallback: &callbackRecord,
            decompressionSessionOut: &session
        )
        
        guard status == noErr, let createdSession = session else {
            throw VideoDecoderError.decompressionSessionFailed(status)
        }
        
        decompressionSession = createdSession
        currentFormatDescription = formatDescription
        logger.info("Created decompression session for codec: \(fourCCString)")
        return createdSession
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

private extension VTVideoDecoder {
    func codecType(for codec: Codec) throws -> (CMVideoCodecType, String) {
        switch codec.fourCC {
        case .avc1:
            return (kCMVideoCodecType_H264, "AVC1")
        case .hvc1:
            return (kCMVideoCodecType_HEVC, "HVC1")
        default:
            throw VideoDecoderError.unsupportedCodec(codec.fourCC.stringRepresentation)
        }
    }
    
    func requestedPixelFormat(from options: [String: String], preferred: OSType?) -> OSType? {
        if let preferred {
            return preferred
        }
        guard let value = options[CodecOptionKey.colorFormat.rawValue]?.lowercased() else {
            return nil
        }
        
        switch value {
        case CodecColorFormat.yuv444.rawValue:
            return kCVPixelFormatType_444YpCbCr8BiPlanarVideoRange
        case CodecColorFormat.yuv420.rawValue:
            fallthrough
        default:
            return kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        }
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
    
    func pts(fromMicroseconds value: UInt64) -> CMTime {
        CMTime(value: CMTimeValue(value), timescale: 1_000_000)
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
