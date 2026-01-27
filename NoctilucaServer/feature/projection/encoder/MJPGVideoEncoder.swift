import Foundation
import AVFoundation
import CoreImage
import ImageIO
import Metal
import SiriusKit
import UniformTypeIdentifiers
import VideoToolbox

import libturbojpeg

final class MJPGVideoEncoder: VideoEncoder {
    private let logger = NoctilucaLogger(category: "MJPGVideoEncoder")
    private let workerQueue: DispatchQueue
    private let callbackQueue: DispatchQueue
    private let ciContext: CIContext

    fileprivate var configuration: VideoEncoderConfiguration?

    private var colorFormat: CodecOptionValue = .kColorFormatYUV420
    private var compressionLevel: Int32 = 90
    private var subsampling: Int32 = TJSAMP_420.rawValue
    private var tileSize: Int = 256

    private var isStarted = false

    let events: AsyncStream<VideoEncoderEvent>
    fileprivate let continuation: AsyncStream<VideoEncoderEvent>.Continuation

    private var frameTiler: FrameTiler!
    private var frameTileDiffer: FrameTileDiffer!
    
    private var compressHandle: tjhandle? = nil
    

    init() {
        self.workerQueue = DispatchQueue(label: "tech.unstablers.noctiluca.mjpgencoder.worker")
        self.callbackQueue = DispatchQueue(label: "tech.unstablers.noctiluca.mjpgencoder.callback")
        if let device = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: device)
        } else {
            self.ciContext = CIContext()
        }
        
        var continuationLocal: AsyncStream<VideoEncoderEvent>.Continuation!
        
        self.events = AsyncStream<VideoEncoderEvent>(VideoEncoderEvent.self, bufferingPolicy: .unbounded) { continuation in
            continuationLocal = continuation
        }
        
        self.continuation = continuationLocal
    }
    
    init(workerQueue: DispatchQueue, callbackQueue: DispatchQueue) {
        self.workerQueue = workerQueue
        self.callbackQueue = callbackQueue
        if let device = MTLCreateSystemDefaultDevice() {
            self.ciContext = CIContext(mtlDevice: device)
        } else {
            self.ciContext = CIContext()
        }
        
        var continuationLocal: AsyncStream<VideoEncoderEvent>.Continuation!
        
        self.events = AsyncStream<VideoEncoderEvent>(VideoEncoderEvent.self, bufferingPolicy: .unbounded) { continuation in
            continuationLocal = continuation
        }
        
        self.continuation = continuationLocal
    }
    
    deinit {
        continuation.finish()
        if let handle = compressHandle {
            tjDestroy(handle)
            compressHandle = nil
        }
    }
    
    func prepare(with configuration: VideoEncoderConfiguration) throws {
        guard self.configuration == nil else {
            throw VideoEncoderError.alreadyPrepared
        }
        
        guard configuration.codec.fourCC == .mjpg else {
            throw VideoEncoderError.unsupportedCodec(configuration.codec.fourCC.stringRepresentation)
        }
        
        self.configuration = configuration
        
        self.compressHandle = tjInitCompress()
        guard self.compressHandle != nil else {
            throw MJPGVideoEncoderError.compressorUnavailable
        }

        // MJPG: kColorFormatAuto는 YUV420과 동일하게 처리
        if let configuredColorFormat = configuration.codec.option(.colorFormat) {
            self.colorFormat = (configuredColorFormat == .kColorFormatAuto) ? .kColorFormatYUV420 : configuredColorFormat
        } else {
            self.colorFormat = .kColorFormatYUV420
        }
        self.subsampling = self.jpegSubsampling(for: self.colorFormat)
        
        // JPEG quality (1...100)
        let levelString = configuration.codec.option(.compressionLevel)?.rawValue ?? "90"
        if let parsedLevel = Int32(levelString) {
            self.compressionLevel = max(1, min(100, parsedLevel))
        } else {
            self.compressionLevel = 90
        }

        // 타일 사이즈
        let tileSizeString = configuration.codec.option(.tileSize)?.rawValue ?? "256"
        if let parsedTileSize = Int(tileSizeString), parsedTileSize > 0 {
            self.tileSize = parsedTileSize
        } else {
            self.tileSize = 256
        }

        // 타일러와 디퍼 생성
        self.frameTiler = FrameTiler(tileSize: self.tileSize)
        self.frameTileDiffer = FrameTileDiffer()
    }
    
    func start() throws {
        guard configuration != nil else {
            throw VideoEncoderError.notPrepared
        }
        isStarted = true
    }
    
    func stop() throws {
        workerQueue.sync {
            isStarted = false
        }
    }
    
    func flush() throws {
        /*
        guard let session = compressionSession else { return }
        VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
         */
    }
    
    func encode(frameID: UInt64, sampleBuffer: CMSampleBuffer) throws {
        guard isStarted else {
            let error = VideoEncoderError.notStarted
            continuation.yield(with: .success(.errorOccurred(error)))
            throw error
        }
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            let error = VideoEncoderError.invalidSampleBuffer
            continuation.yield(with: .success(.errorOccurred(error)))
            throw error
        }
        
        do {
            try workerQueue.sync {
                // RGB888 or RGB565
                let pixelBuffer: CVPixelBuffer
                if let imageBuffer = sampleBuffer.imageBuffer {
                    let pixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer)
                    if pixelFormat == kCVPixelFormatType_32BGRA {
                        pixelBuffer = imageBuffer
                    } else {
                        let rgbSampleBuffer = try sampleBuffer.convertToRGBIfNeeded(required: colorFormat, ciContext: ciContext)
                        guard let convertedBuffer = rgbSampleBuffer.imageBuffer else {
                            throw VideoEncoderError.invalidSampleBuffer
                        }
                        pixelBuffer = convertedBuffer
                    }
                } else {
                    throw VideoEncoderError.invalidSampleBuffer
                }
                
                // 64x64로 타일 인코딩을 행한다
                let rgbTiles = frameTiler.tile(pixelBuffer)
                guard !rgbTiles.isEmpty else { return }
                
                // 기존 프레임과의 diff를 행한다
                let diffIndices = frameTileDiffer.feed(rgbTiles)
                if diffIndices.isEmpty {
                    return
                }
                
                // 변경된 각 타일을 JPEG로 인코딩한다
                // TODO: 가능한 경우 병렬 처리를 행한다
                
                let tileSize = frameTiler.tileSize
                let paddedWidth = paddedDimension(CVPixelBufferGetWidth(pixelBuffer), tileSize: tileSize)
                let tilesPerRow = max(1, paddedWidth / tileSize)
                
                var encodedTiles: [ProjectionFrameTile] = []
                encodedTiles.reserveCapacity(diffIndices.count)
                
                let jpegQuality = self.jpegQuality()
                for index in diffIndices {
                    let tile = rgbTiles[index]
                    
                    let jpeg = try encodeJPEG(tile, quality: jpegQuality)

                    let geometry = geometryForTile(
                        index: index,
                        tilesPerRow: tilesPerRow,
                        tileSize: tileSize
                    )
                    
                    encodedTiles.append(ProjectionFrameTile(geometry: geometry, data: jpeg))
                }
                
                // emit frame
                // see SiriusKit/channel/msgdef/v1/channels/projection_data/TiledFrame.swift
                
                let frameData = try ProjectionFrameTile.encode(encodedTiles)
                guard frameData.count <= Int(UInt32.max) else {
                    throw VideoEncoderError.payloadTooLarge(frameData.count)
                }
                
                let isKeyframe = diffIndices.count == rgbTiles.count
                let frameHeader = FrameDataHeader(
                    frameID: frameID,
                    frameLength: UInt32(frameData.count),
                    presentationTimestamp: self.microseconds(from: CMSampleBufferGetPresentationTimeStamp(sampleBuffer)),
                    flags: isKeyframe ? [.isKeyframe] : []
                )
                let frame = EncodedFrame(header: consume frameHeader, data: consume frameData, formatDescription: nil)
                continuation.yield(with: .success(.frameEncoded(consume frame)))
            }
        } catch {
            continuation.yield(with: .success(.errorOccurred(error)))
            throw error
        }
    }
    
    // MARK: - On-the-fly controls
    
    func forceKeyframe() {
        logger.info("Force keyframe requested.")
        // 타일 차이 기록 초기화를 행한다
        self.frameTileDiffer.reset()
    }
    
    @discardableResult
    func updateTargetBitrate(_ bitrateKbps: Int) -> Bool {
        return true
    }
    
    @discardableResult
    func updateMaxBitrate(bitrateKbps: Int) -> Bool {
        return true
    }
}

// MARK: - Helpers

    private enum MJPGVideoEncoderError: LocalizedError {
        case compressorUnavailable
        case cgImageCreationFailed
        case destinationCreationFailed
        case destinationFinalizeFailed
    
    var errorDescription: String? {
        switch self {
        case .compressorUnavailable:
            return "MJPG compressor is not available."
        case .cgImageCreationFailed:
            return "MJPG failed to create CGImage from pixel buffer."
        case .destinationCreationFailed:
            return "MJPG failed to create image destination."
        case .destinationFinalizeFailed:
            return "MJPG failed to finalize image destination."
        }
    }
}

private extension MJPGVideoEncoder {
    func jpegQuality() -> Int32 {
        return max(1, min(100, compressionLevel))
    }

    func jpegSubsampling(for colorFormat: CodecOptionValue) -> Int32 {
        if colorFormat == .kColorFormatYUV444 {
            return TJSAMP_444.rawValue
        }
        return TJSAMP_420.rawValue
    }
    
    func encodeJPEG(_ pixelBuffer: CVPixelBuffer, quality: Int32) throws -> Data {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            // FIXME
            throw MJPGVideoEncoderError.cgImageCreationFailed
        }
        
        
        guard let handle = compressHandle else {
            throw MJPGVideoEncoderError.compressorUnavailable
        }

        var outPtr: UnsafeMutablePointer<UInt8>? = nil
        var outSize: UInt = 0
        
        let retval = withUnsafeMutablePointer(to: &outSize) { outSizePtr in
            tjCompress2(
                handle,
                baseAddress,
                Int32(width),
                Int32(bytesPerRow),
                Int32(height),
                TJPF_BGRA.rawValue,
                &outPtr,
                outSizePtr,
                subsampling,
                quality,
                0
            )
        }
        
        guard retval == 0 else {
            throw MJPGVideoEncoderError.destinationFinalizeFailed
        }
        
        
        guard let outPtr else {
            throw MJPGVideoEncoderError.destinationFinalizeFailed
        }

        let data = Data(bytes: outPtr, count: Int(outSize))
        
        tjFree(outPtr)
        
        return consume data
    }
    
    func microseconds(from time: CMTime) -> UInt64 {
        guard time.isValid, time.timescale != 0 else { return 0 }
        let scaled = CMTimeConvertScale(time, timescale: 1_000_000, method: .default)
        if scaled.value < 0 {
            return 0
        }
        return UInt64(scaled.value)
    }
    
    func paddedDimension(_ value: Int, tileSize: Int) -> Int {
        guard tileSize > 0 else { return value }
        return ((value + tileSize - 1) / tileSize) * tileSize
    }
    
    func geometryForTile(index: Int, tilesPerRow: Int, tileSize: Int) -> CGRect {
        let x = (index % tilesPerRow) * tileSize
        let y = (index / tilesPerRow) * tileSize
        return CGRect(x: x, y: y, width: tileSize, height: tileSize)
    }
}

// MARK: - CMSampleBuffer RGB Conversion

private extension CMSampleBuffer {
    func convertToRGBIfNeeded(required: CodecOptionValue, ciContext: CIContext) throws -> CMSampleBuffer {
        _ = required
        guard let imageBuffer = CMSampleBufferGetImageBuffer(self) else {
            throw VideoEncoderError.invalidSampleBuffer
        }
        
        let desiredPixelFormat = kCVPixelFormatType_32BGRA
        let currentPixelFormat = CVPixelBufferGetPixelFormatType(imageBuffer)
        if currentPixelFormat == desiredPixelFormat {
            return self
        }
        
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)
        
        var convertedBuffer: CVPixelBuffer?
        let attrs: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue as Any,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue as Any,
            kCVPixelBufferMetalCompatibilityKey: kCFBooleanTrue as Any
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            desiredPixelFormat,
            attrs,
            &convertedBuffer
        )
        
        guard status == kCVReturnSuccess, let convertedBuffer else {
            throw VideoEncoderError.invalidSampleBuffer
        }
        
        let ciImage = CIImage(cvImageBuffer: imageBuffer)
        let colorSpace = CVImageBufferGetColorSpace(imageBuffer)?.takeUnretainedValue() ?? CGColorSpaceCreateDeviceRGB()
        CVBufferPropagateAttachments(imageBuffer, convertedBuffer)
        ciContext.render(ciImage, to: convertedBuffer, bounds: ciImage.extent, colorSpace: colorSpace)
        
        var timingInfo = CMSampleTimingInfo()
        _ = CMSampleBufferGetSampleTimingInfo(self, at: 0, timingInfoOut: &timingInfo)
        
        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: convertedBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw VideoEncoderError.invalidSampleBuffer
        }
        
        var convertedSampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: convertedBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timingInfo,
            sampleBufferOut: &convertedSampleBuffer
        )
        
        guard sampleStatus == noErr, let convertedSampleBuffer else {
            throw VideoEncoderError.invalidSampleBuffer
        }
        
        return convertedSampleBuffer
    }
}
