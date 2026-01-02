import Foundation
import AVFoundation
import CoreImage
import Metal
import SiriusKit

import libzstd

/// ZRLE (RLE + Zstd) 비디오 인코더
final class ZRLEVideoEncoder: VideoEncoder {
    private let logger = NoctilucaLogger(category: "ZRLEVideoEncoder")
    private let workerQueue: DispatchQueue
    private let callbackQueue: DispatchQueue
    private let ciContext: CIContext

    fileprivate var configuration: VideoEncoderConfiguration?

    private var colorFormat: CodecOptionValue = .kColorFormatRGB888
    private var compressionLevel: Int32 = 3

    private var isStarted = false
    
    let events: AsyncStream<VideoEncoderEvent>
    fileprivate let continuation: AsyncStream<VideoEncoderEvent>.Continuation
    
    let frameTiler = FrameTiler(tileSize: 64)
    let frameTileDiffer = FrameTileDiffer()
    
    init() {
        self.workerQueue = DispatchQueue(label: "tech.unstablers.noctiluca.zrleencoder.worker")
        self.callbackQueue = DispatchQueue(label: "tech.unstablers.noctiluca.zrleencoder.callback")
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
    
    func prepare(with configuration: VideoEncoderConfiguration) throws {
        guard self.configuration == nil else {
            throw VideoEncoderError.alreadyPrepared
        }
        
        guard configuration.codec.fourCC == .zrle else {
            throw VideoEncoderError.unsupportedCodec(configuration.codec.fourCC.stringRepresentation)
        }
        
        self.configuration = configuration
        
        // RGB888 or RGB565
        if let configuredColorFormat = configuration.codec.option(.colorFormat) {
            self.colorFormat = configuredColorFormat
        } else {
            self.colorFormat = .kColorFormatRGB888
        }
        
        // Zstd compression level (1...22)
        let levelString = configuration.codec.option(.compressionLevel)?.rawValue ?? "3"
        if let parsedLevel = Int32(levelString) {
            self.compressionLevel = max(1, min(22, parsedLevel))
        } else {
            self.compressionLevel = 3
        }
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
                let rgbSampleBuffer = try sampleBuffer.convertToRGBIfNeeded(required: colorFormat, ciContext: ciContext)
            
                guard let pixelBuffer = rgbSampleBuffer.imageBuffer else {
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
                
                // 변경된 각 타일에 대해 RLE 압축을 수행한 뒤, Zstd로 다시 압축한다
                // TODO: 가능한 경우 병렬 처리를 행한다
                
                let tileSize = frameTiler.tileSize
                let paddedWidth = paddedDimension(CVPixelBufferGetWidth(pixelBuffer), tileSize: tileSize)
                let tilesPerRow = max(1, paddedWidth / tileSize)
                
                var encodedTiles: [ProjectionFrameTile] = []
                encodedTiles.reserveCapacity(diffIndices.count)
                
                for index in diffIndices {
                    let tile = rgbTiles[index]
                    let rle = try self.rleCompress(tile, colorFormat: colorFormat)
                    let zstd = try self.zstdCompress(rle, compressionLevel: self.compressionLevel)
                    
                    let geometry = geometryForTile(
                        index: index,
                        tilesPerRow: tilesPerRow,
                        tileSize: tileSize
                    )
                    
                    encodedTiles.append(ProjectionFrameTile(geometry: geometry, data: zstd))
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

private enum ZRLEVideoEncoderError: LocalizedError {
    case compressionFailed(String)
    case unsupportedPixelFormat(OSType)
    
    var errorDescription: String? {
        switch self {
        case .compressionFailed(let reason):
            return "ZRLE compression failed: \(reason)"
        case .unsupportedPixelFormat(let format):
            return "Unsupported pixel format: \(format)"
        }
    }
}

private extension ZRLEVideoEncoder {
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
    
    func rleCompress(_ pixelBuffer: CVPixelBuffer, colorFormat: CodecOptionValue) throws -> Data {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard format == kCVPixelFormatType_32BGRA else {
            throw ZRLEVideoEncoderError.unsupportedPixelFormat(format)
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw VideoEncoderError.invalidSampleBuffer
        }
        
        let pixelBytes = baseAddress.assumingMemoryBound(to: UInt8.self)
        let useRGB565 = (colorFormat == .kColorFormatRGB565)
        
        var output = Data()
        
        for row in 0..<height {
            let rowPtr = pixelBytes + (row * bytesPerRow)
            
            var runCount: UInt32 = 0
            var prevB: UInt8 = 0
            var prevG: UInt8 = 0
            var prevR: UInt8 = 0
            var prev565: UInt16 = 0
            
            for col in 0..<width {
                let pixelPtr = rowPtr + (col * 4)
                let b = pixelPtr[0]
                let g = pixelPtr[1]
                let r = pixelPtr[2]
                
                if runCount == 0 {
                    if useRGB565 {
                        prev565 = packRGB565(r: r, g: g, b: b)
                    } else {
                        prevB = b
                        prevG = g
                        prevR = r
                    }
                    runCount = 1
                    continue
                }
                
                if useRGB565 {
                    let current = packRGB565(r: r, g: g, b: b)
                    if current == prev565 && runCount < UInt32.max {
                        runCount &+= 1
                    } else {
                        appendRun(&output, count: runCount, pixel565: prev565)
                        prev565 = current
                        runCount = 1
                    }
                } else {
                    if b == prevB && g == prevG && r == prevR && runCount < UInt32.max {
                        runCount &+= 1
                    } else {
                        appendRun(&output, count: runCount, b: prevB, g: prevG, r: prevR)
                        prevB = b
                        prevG = g
                        prevR = r
                        runCount = 1
                    }
                }
            }
            
            if runCount > 0 {
                if useRGB565 {
                    appendRun(&output, count: runCount, pixel565: prev565)
                } else {
                    appendRun(&output, count: runCount, b: prevB, g: prevG, r: prevR)
                }
            }
        }
        
        return output
    }
    
    func appendRun(_ data: inout Data, count: UInt32, b: UInt8, g: UInt8, r: UInt8) {
        let countLE = count.littleEndian
        withUnsafeBytes(of: countLE) { data.append(contentsOf: $0) }
        data.append(b)
        data.append(g)
        data.append(r)
    }
    
    func appendRun(_ data: inout Data, count: UInt32, pixel565: UInt16) {
        let countLE = count.littleEndian
        withUnsafeBytes(of: countLE) { data.append(contentsOf: $0) }
        let pixelLE = pixel565.littleEndian
        withUnsafeBytes(of: pixelLE) { data.append(contentsOf: $0) }
    }
    
    func packRGB565(r: UInt8, g: UInt8, b: UInt8) -> UInt16 {
        let r5 = UInt16(r >> 3)
        let g6 = UInt16(g >> 2)
        let b5 = UInt16(b >> 3)
        return (r5 << 11) | (g6 << 5) | b5
    }
    
    func zstdCompress(_ data: Data, compressionLevel: Int32) throws -> Data {
        let bound = ZSTD_compressBound(data.count)
        var output = Data(count: bound)
        
        let result = data.withUnsafeBytes { inputPtr in
            output.withUnsafeMutableBytes { outputPtr in
                ZSTD_compress(
                    outputPtr.baseAddress,
                    bound,
                    inputPtr.baseAddress,
                    data.count,
                    compressionLevel
                )
            }
        }
        
        if ZSTD_isError(result) != 0 {
            let reason = String(cString: ZSTD_getErrorName(result))
            throw ZRLEVideoEncoderError.compressionFailed(reason)
        }
        
        output.count = result
        return output
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
