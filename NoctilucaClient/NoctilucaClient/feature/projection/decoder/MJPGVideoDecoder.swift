import Foundation
import CoreMedia
import CoreVideo
import CoreGraphics
import ImageIO
import SiriusKitClient

import Accelerate

import UniformTypeIdentifiers

import libturbojpeg

/// MJPG (tiled JPEG) 소프트웨어 디코더
final class MJPGVideoDecoder: VideoDecoder {
    weak var delegate: VideoDecoderDelegate?
    
    private let workerQueue: DispatchQueue
    private let callbackQueue: DispatchQueue
    
    private var configuration: VideoDecoderConfiguration?
    private var isStarted = false
    
    private var pixelBufferPool: CVPixelBufferPool?
    private var baseFrameBuffer: CVPixelBuffer?
    private var frameWidth: Int = 0
    private var frameHeight: Int = 0
    private var cachedFormatDescription: CMFormatDescription?
    
    private var decompressHandle: tjhandle? = nil
    
    init() {
        self.workerQueue = DispatchQueue(label: "pl.unstabler.noctiluca.decoder.mjpg.worker")
        self.callbackQueue = DispatchQueue(label: "pl.unstabler.noctiluca.decoder.mjpg.callback")
    }
    
    init(workerQueue: DispatchQueue, callbackQueue: DispatchQueue) {
        self.workerQueue = workerQueue
        self.callbackQueue = callbackQueue
    }
    
    deinit {
        if let handle = decompressHandle {
            tjDestroy(handle)
            decompressHandle = nil
        }
    }
    
    func prepare(with configuration: VideoDecoderConfiguration) throws {
        guard self.configuration == nil else {
            throw VideoDecoderError.alreadyPrepared
        }
        guard configuration.codec.fourCC == .mjpg else {
            throw VideoDecoderError.unsupportedCodec(configuration.codec.fourCC.stringRepresentation)
        }
        self.configuration = configuration
        
        self.decompressHandle = tjInitDecompress()
    }
    
    func start() throws {
        guard configuration != nil else { throw VideoDecoderError.notPrepared }
        isStarted = true
    }
    
    func stop() throws {
        workerQueue.sync {
            baseFrameBuffer = nil
            pixelBufferPool = nil
            cachedFormatDescription = nil
            frameWidth = 0
            frameHeight = 0
            isStarted = false
        }
    }
    
    func flush() throws {
        workerQueue.sync {
            baseFrameBuffer = nil
            cachedFormatDescription = nil
        }
    }
    
    func decode(_ frame: EncodedFrameInput) throws {
        guard isStarted else { throw VideoDecoderError.notStarted }
        let expectedLength = Int(frame.header.frameLength)
        guard expectedLength == frame.data.count else {
            throw VideoDecoderError.payloadLengthMismatch(expected: expectedLength, actual: frame.data.count)
        }
        
        let decodeStart = DispatchTime.now()
        workerQueue.sync {
            do {
                try self.decodeFrame(frame, decodeStart: decodeStart)
            } catch {
                let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                self.callbackQueue.async {
                    self.delegate?.videoDecoder(self, didDropFrameWithID: frame.header.frameID, reason: reason)
                }
            }
        }
    }
}

// MARK: - Decode pipeline

private extension MJPGVideoDecoder {
    func decodeFrame(_ frame: EncodedFrameInput, decodeStart: DispatchTime) throws {
        let tiles = try decodeTiles(from: frame.data)
        guard tiles.isEmpty == false else {
            throw MJPGVideoDecoderError.invalidTileData("empty tile list")
        }
        
        let isKeyframe = frame.header.flags.contains(.isKeyframe)
        if isKeyframe {
            baseFrameBuffer = nil
        } else if baseFrameBuffer == nil {
            throw MJPGVideoDecoderError.missingKeyframe
        }
        
        let targetSize: (width: Int, height: Int)
        if let baseFrameBuffer, !isKeyframe {
            targetSize = (CVPixelBufferGetWidth(baseFrameBuffer), CVPixelBufferGetHeight(baseFrameBuffer))
        } else {
            targetSize = frameSize(from: tiles)
            guard targetSize.width > 0, targetSize.height > 0 else {
                throw MJPGVideoDecoderError.invalidTileData("invalid frame size")
            }
        }
        
        if targetSize.width != frameWidth || targetSize.height != frameHeight {
            try rebuildPixelBufferPool(width: targetSize.width, height: targetSize.height)
        }
        
        guard let outputBuffer = makePixelBuffer() else {
            throw MJPGVideoDecoderError.pixelBufferUnavailable
        }
        
        if let baseFrameBuffer, !isKeyframe {
            copyPixelBuffer(from: baseFrameBuffer, to: outputBuffer)
        } else {
            clearPixelBuffer(outputBuffer)
        }
        
        try applyTiles(tiles, to: outputBuffer)
        baseFrameBuffer = outputBuffer
        
        let formatDescription = try formatDescription(for: outputBuffer)
        let pts = CMTime(value: CMTimeValue(frame.header.presentationTimestamp), timescale: 1_000_000)
        let decodeEnd = DispatchTime.now()
        let decodeMs = max(0, Double(decodeEnd.uptimeNanoseconds - decodeStart.uptimeNanoseconds) / 1_000_000.0)
        let decodedFrame = DecodedFrame(
            pixelBuffer: outputBuffer,
            pts: pts,
            isKeyFrame: isKeyframe,
            formatDescription: formatDescription,
            decodeTimeMs: decodeMs
        )
        
        callbackQueue.async {
            self.delegate?.videoDecoder(self, didDecode: decodedFrame)
        }
    }
}

// MARK: - Tiles

private struct MJPGTile {
    let originX: Int
    let originY: Int
    let width: Int
    let height: Int
    let data: Data
}

private extension MJPGVideoDecoder {
    func decodeTiles(from data: Data) throws -> [MJPGTile] {
        var offset = 0
        guard data.count >= 4 else {
            throw MJPGVideoDecoderError.invalidTileData("insufficient header")
        }
        let tileCount = readUInt32BE(data, offset: &offset)
        if tileCount == 0 { return [] }
        
        var tiles: [MJPGTile] = []
        tiles.reserveCapacity(Int(tileCount))
        
        for _ in 0..<tileCount {
            guard offset + 12 <= data.count else {
                throw MJPGVideoDecoderError.invalidTileData("truncated tile header")
            }
            let x = Int(readUInt16BE(data, offset: &offset))
            let y = Int(readUInt16BE(data, offset: &offset))
            let w = Int(readUInt16BE(data, offset: &offset))
            let h = Int(readUInt16BE(data, offset: &offset))
            let length = Int(readUInt32BE(data, offset: &offset))
            
            guard length >= 0, offset + length <= data.count else {
                throw MJPGVideoDecoderError.invalidTileData("truncated tile payload")
            }
            let tileData = data.subdata(in: offset..<(offset + length))
            offset += length
            
            tiles.append(MJPGTile(originX: x, originY: y, width: w, height: h, data: tileData))
        }
        
        return tiles
    }
    
    func applyTiles(_ tiles: [MJPGTile], to pixelBuffer: CVPixelBuffer) throws {
        let outputWidth = CVPixelBufferGetWidth(pixelBuffer)
        let outputHeight = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw MJPGVideoDecoderError.pixelBufferUnavailable
        }
        
        /*
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let alphaInfo = CGImageAlphaInfo.premultipliedFirst
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(CGBitmapInfo(rawValue: alphaInfo.rawValue))
        guard let context = CGContext(
            data: baseAddress,
            width: outputWidth,
            height: outputHeight,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            throw MJPGVideoDecoderError.contextCreationFailed
        }
        
        context.setBlendMode(.copy)
        context.interpolationQuality = .none
         */
        
        for tile in tiles {
            guard tile.originX >= 0, tile.originY >= 0 else {
                throw MJPGVideoDecoderError.invalidTileData("negative tile origin")
            }
            guard tile.width > 0, tile.height > 0 else {
                throw MJPGVideoDecoderError.invalidTileData("invalid tile size")
            }
            guard tile.originX + tile.width <= outputWidth,
                  tile.originY + tile.height <= outputHeight else {
                throw MJPGVideoDecoderError.invalidTileData("tile out of bounds")
            }
            
            let decoded = try decodeJPEG(tile)
            // let flippedY = outputHeight - tile.originY - tile.height
            let rect = CGRect(x: tile.originX, y: tile.originY, width: tile.width, height: tile.height)
            
            let tileBytesPerRow = tile.width * 4 // FIXME
            
            decoded.withUnsafeBytes { decodedPtr in
                for y in 0..<tile.height {
                    let destRow = baseAddress.advanced(by: (tile.originY + y) * bytesPerRow + tile.originX * 4)
                    let srcRow = decodedPtr.baseAddress!.advanced(by: y * tileBytesPerRow)
                    memcpy(destRow, srcRow, tile.width * 4)
                }
            }
            
            // context.draw(cgImage, in: rect)
        }
    }
}

// MARK: - Pixel buffers

private extension MJPGVideoDecoder {
    func rebuildPixelBufferPool(width: Int, height: Int) throws {
        var pool: CVPixelBufferPool?
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        let status = CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attrs as CFDictionary, &pool)
        guard status == kCVReturnSuccess, let pool else {
            throw MJPGVideoDecoderError.pixelBufferUnavailable
        }
        
        pixelBufferPool = pool
        frameWidth = width
        frameHeight = height
        cachedFormatDescription = nil
    }
    
    func makePixelBuffer() -> CVPixelBuffer? {
        guard let pool = pixelBufferPool else { return nil }
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer)
        guard status == kCVReturnSuccess else { return nil }
        return buffer
    }
    
    func copyPixelBuffer(from source: CVPixelBuffer, to destination: CVPixelBuffer) {
        let sourceWidth = CVPixelBufferGetWidth(source)
        let sourceHeight = CVPixelBufferGetHeight(source)
        let destWidth = CVPixelBufferGetWidth(destination)
        let destHeight = CVPixelBufferGetHeight(destination)
        guard sourceWidth == destWidth, sourceHeight == destHeight else {
            clearPixelBuffer(destination)
            return
        }
        
        CVPixelBufferLockBaseAddress(source, .readOnly)
        CVPixelBufferLockBaseAddress(destination, [])
        defer {
            CVPixelBufferUnlockBaseAddress(source, .readOnly)
            CVPixelBufferUnlockBaseAddress(destination, [])
        }
        
        guard let sourceBase = CVPixelBufferGetBaseAddress(source),
              let destBase = CVPixelBufferGetBaseAddress(destination) else {
            return
        }
        
        let sourceBytesPerRow = CVPixelBufferGetBytesPerRow(source)
        let destBytesPerRow = CVPixelBufferGetBytesPerRow(destination)
        let bytesToCopy = min(sourceBytesPerRow, destBytesPerRow)
        
        for row in 0..<sourceHeight {
            let src = sourceBase.advanced(by: row * sourceBytesPerRow)
            let dst = destBase.advanced(by: row * destBytesPerRow)
            memcpy(dst, src, bytesToCopy)
        }
    }
    
    func clearPixelBuffer(_ buffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        memset(base, 0, bytesPerRow * height)
    }
    
    func formatDescription(for buffer: CVPixelBuffer) throws -> CMFormatDescription {
        if let cachedFormatDescription {
            return cachedFormatDescription
        }
        var description: CMVideoFormatDescription?
        let status = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: buffer,
            formatDescriptionOut: &description
        )
        guard status == noErr, let description else {
            throw MJPGVideoDecoderError.invalidTileData("format description creation failed")
        }
        cachedFormatDescription = description
        return description
    }
}

// MARK: - Helpers

private extension MJPGVideoDecoder {
    func frameSize(from tiles: [MJPGTile]) -> (width: Int, height: Int) {
        var maxX = 0
        var maxY = 0
        for tile in tiles {
            maxX = max(maxX, tile.originX + tile.width)
            maxY = max(maxY, tile.originY + tile.height)
        }
        return (maxX, maxY)
    }
    
    func decodeJPEG(_ tile: borrowing MJPGTile) throws -> Data {
        var dstData = Data(count: Int(tile.width) * Int(tile.height) * 4)
        
        let retval = dstData.withUnsafeMutableBytes { dstPtr in
            tile.data.withUnsafeBytes { jpegPtr in
                tjDecompress2(
                    self.decompressHandle!,
                    jpegPtr,
                    UInt(tile.data.count),
                    dstPtr,
                    Int32(tile.width),
                    0,
                    Int32(tile.height),
                    TJPF_BGRA.rawValue,
                    TJFLAG_FASTDCT
                )
            }
        }
        
        guard retval == 0 else {
            throw MJPGVideoDecoderError.jpegDecodeFailed
        }
        
        return consume dstData
        
        /*
        let options: CFDictionary = [
            kCGImageSourceShouldCache: kCFBooleanTrue,
            kCGImageSourceShouldCacheImmediately: kCFBooleanTrue,
            kCGImageSourceTypeIdentifierHint: UTType.jpeg.identifier
        ] as CFDictionary
        
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else {
            throw MJPGVideoDecoderError.jpegDecodeFailed
        }
        
        guard CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(source, 0, options) else {
            throw MJPGVideoDecoderError.jpegDecodeFailed
        }
        return image
         */
    }
    
    func readUInt16BE(_ data: Data, offset: inout Int) -> UInt16 {
        let value = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self) }.bigEndian
        offset += 2
        return value
    }
    
    func readUInt32BE(_ data: Data, offset: inout Int) -> UInt32 {
        let value = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        offset += 4
        return value
    }
}

enum MJPGVideoDecoderError: LocalizedError {
    case jpegDecodeFailed
    case contextCreationFailed
    case invalidTileData(String)
    case pixelBufferUnavailable
    case missingKeyframe
    
    var errorDescription: String? {
        switch self {
        case .jpegDecodeFailed:
            return "MJPG JPEG decode failed"
        case .contextCreationFailed:
            return "MJPG failed to create bitmap context"
        case .invalidTileData(let reason):
            return "MJPG tile data invalid: \(reason)"
        case .pixelBufferUnavailable:
            return "MJPG pixel buffer unavailable"
        case .missingKeyframe:
            return "MJPG missing keyframe"
        }
    }
}
