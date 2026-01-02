import Foundation
import CoreMedia
import CoreVideo
import SiriusKitClient

import libzstd

/// ZRLE (RLE + Zstd) 소프트웨어 디코더
final class ZRLEVideoDecoder: VideoDecoder {
    weak var delegate: VideoDecoderDelegate?
    
    private let workerQueue: DispatchQueue
    private let callbackQueue: DispatchQueue
    
    private var configuration: VideoDecoderConfiguration?
    private var isStarted = false
    private var colorFormat: CodecOptionValue = .kColorFormatRGB888
    
    private var pixelBufferPool: CVPixelBufferPool?
    private var baseFrameBuffer: CVPixelBuffer?
    private var frameWidth: Int = 0
    private var frameHeight: Int = 0
    private var cachedFormatDescription: CMFormatDescription?
    
    init() {
        self.workerQueue = DispatchQueue(label: "pl.unstabler.noctiluca.decoder.zrle.worker")
        self.callbackQueue = DispatchQueue(label: "pl.unstabler.noctiluca.decoder.zrle.callback")
    }
    
    init(workerQueue: DispatchQueue, callbackQueue: DispatchQueue) {
        self.workerQueue = workerQueue
        self.callbackQueue = callbackQueue
    }
    
    func prepare(with configuration: VideoDecoderConfiguration) throws {
        guard self.configuration == nil else {
            throw VideoDecoderError.alreadyPrepared
        }
        guard configuration.codec.fourCC == .zrle else {
            throw VideoDecoderError.unsupportedCodec(configuration.codec.fourCC.stringRepresentation)
        }
        self.configuration = configuration
        if let configuredColorFormat = configuration.codec.option(.colorFormat) {
            self.colorFormat = configuredColorFormat
        } else {
            self.colorFormat = .kColorFormatRGB888
        }
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

private extension ZRLEVideoDecoder {
    func decodeFrame(_ frame: EncodedFrameInput, decodeStart: DispatchTime) throws {
        let tiles = try decodeTiles(from: frame.data)
        guard tiles.isEmpty == false else {
            throw ZRLEVideoDecoderError.invalidTileData("empty tile list")
        }
        
        let isKeyframe = frame.header.flags.contains(.isKeyframe)
        if isKeyframe {
            baseFrameBuffer = nil
        } else if baseFrameBuffer == nil {
            throw ZRLEVideoDecoderError.missingKeyframe
        }
        
        let targetSize: (width: Int, height: Int)
        if let baseFrameBuffer, !isKeyframe {
            targetSize = (CVPixelBufferGetWidth(baseFrameBuffer), CVPixelBufferGetHeight(baseFrameBuffer))
        } else {
            targetSize = frameSize(from: tiles)
            guard targetSize.width > 0, targetSize.height > 0 else {
                throw ZRLEVideoDecoderError.invalidTileData("invalid frame size")
            }
        }
        
        if targetSize.width != frameWidth || targetSize.height != frameHeight {
            try rebuildPixelBufferPool(width: targetSize.width, height: targetSize.height)
        }
        
        guard let outputBuffer = makePixelBuffer() else {
            throw ZRLEVideoDecoderError.pixelBufferUnavailable
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

// MARK: - Tiles & RLE

private struct ZRLETile {
    let originX: Int
    let originY: Int
    let width: Int
    let height: Int
    let data: Data
}

private extension ZRLEVideoDecoder {
    func decodeTiles(from data: Data) throws -> [ZRLETile] {
        var offset = 0
        guard data.count >= 4 else {
            throw ZRLEVideoDecoderError.invalidTileData("insufficient header")
        }
        let tileCount = readUInt32BE(data, offset: &offset)
        if tileCount == 0 { return [] }
        
        var tiles: [ZRLETile] = []
        tiles.reserveCapacity(Int(tileCount))
        
        for _ in 0..<tileCount {
            guard offset + 12 <= data.count else {
                throw ZRLEVideoDecoderError.invalidTileData("truncated tile header")
            }
            let x = Int(readUInt16BE(data, offset: &offset))
            let y = Int(readUInt16BE(data, offset: &offset))
            let w = Int(readUInt16BE(data, offset: &offset))
            let h = Int(readUInt16BE(data, offset: &offset))
            let length = Int(readUInt32BE(data, offset: &offset))
            
            guard length >= 0, offset + length <= data.count else {
                throw ZRLEVideoDecoderError.invalidTileData("truncated tile payload")
            }
            let tileData = data.subdata(in: offset..<(offset + length))
            offset += length
            
            tiles.append(ZRLETile(originX: x, originY: y, width: w, height: h, data: tileData))
        }
        
        return tiles
    }
    
    func applyTiles(_ tiles: [ZRLETile], to pixelBuffer: CVPixelBuffer) throws {
        let outputWidth = CVPixelBufferGetWidth(pixelBuffer)
        let outputHeight = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw ZRLEVideoDecoderError.pixelBufferUnavailable
        }
        let output = baseAddress.assumingMemoryBound(to: UInt8.self)
        let useRGB565 = (colorFormat == .kColorFormatRGB565)
        
        for tile in tiles {
            guard tile.originX >= 0, tile.originY >= 0 else {
                throw ZRLEVideoDecoderError.invalidTileData("negative tile origin")
            }
            guard tile.width > 0, tile.height > 0 else {
                throw ZRLEVideoDecoderError.invalidTileData("invalid tile size")
            }
            guard tile.originX + tile.width <= outputWidth,
                  tile.originY + tile.height <= outputHeight else {
                throw ZRLEVideoDecoderError.invalidTileData("tile out of bounds")
            }
            
            let rleData = try zstdDecompress(tile.data)
            try applyRLE(
                rleData,
                to: output,
                bytesPerRow: bytesPerRow,
                tile: tile,
                useRGB565: useRGB565
            )
        }
    }
    
    func applyRLE(
        _ data: Data,
        to output: UnsafeMutablePointer<UInt8>,
        bytesPerRow: Int,
        tile: ZRLETile,
        useRGB565: Bool
    ) throws {
        var offset = 0
        for row in 0..<tile.height {
            var col = 0
            while col < tile.width {
                guard offset + 4 <= data.count else {
                    throw ZRLEVideoDecoderError.invalidTileData("rle header truncated")
                }
                let runCount = Int(readUInt32LE(data, offset: &offset))
                if runCount <= 0 {
                    throw ZRLEVideoDecoderError.invalidTileData("invalid run length")
                }
                guard col + runCount <= tile.width else {
                    throw ZRLEVideoDecoderError.invalidTileData("run exceeds row width")
                }
                
                let b: UInt8
                let g: UInt8
                let r: UInt8
                
                if useRGB565 {
                    guard offset + 2 <= data.count else {
                        throw ZRLEVideoDecoderError.invalidTileData("rgb565 truncated")
                    }
                    let pixel565 = readUInt16LE(data, offset: &offset)
                    let rgb = unpackRGB565(pixel565)
                    b = rgb.b
                    g = rgb.g
                    r = rgb.r
                } else {
                    guard offset + 3 <= data.count else {
                        throw ZRLEVideoDecoderError.invalidTileData("rgb888 truncated")
                    }
                    b = data[offset]
                    g = data[offset + 1]
                    r = data[offset + 2]
                    offset += 3
                }
                
                var pixelPtr = output + ((tile.originY + row) * bytesPerRow) + ((tile.originX + col) * 4)
                for _ in 0..<runCount {
                    pixelPtr[0] = b
                    pixelPtr[1] = g
                    pixelPtr[2] = r
                    pixelPtr[3] = 0xFF
                    pixelPtr += 4
                }
                
                col += runCount
            }
        }
        
        if offset != data.count {
            throw ZRLEVideoDecoderError.invalidTileData("rle payload trailing bytes")
        }
    }
}

// MARK: - Pixel buffers

private extension ZRLEVideoDecoder {
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
            throw ZRLEVideoDecoderError.pixelBufferUnavailable
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
            throw ZRLEVideoDecoderError.invalidTileData("format description creation failed")
        }
        cachedFormatDescription = description
        return description
    }
}

// MARK: - Helpers

private extension ZRLEVideoDecoder {
    func frameSize(from tiles: [ZRLETile]) -> (width: Int, height: Int) {
        var maxX = 0
        var maxY = 0
        for tile in tiles {
            maxX = max(maxX, tile.originX + tile.width)
            maxY = max(maxY, tile.originY + tile.height)
        }
        return (maxX, maxY)
    }
    
    func zstdDecompress(_ data: Data) throws -> Data {
        let contentSize = data.withUnsafeBytes { ZSTD_getFrameContentSize($0.baseAddress, data.count) }
        if contentSize == ZSTD_CONTENTSIZE_ERROR || contentSize == ZSTD_CONTENTSIZE_UNKNOWN {
            throw ZRLEVideoDecoderError.compressionFailed("unknown content size")
        }
        let outputSize = Int(contentSize)
        var output = Data(count: outputSize)
        let result = data.withUnsafeBytes { inputPtr in
            output.withUnsafeMutableBytes { outputPtr in
                ZSTD_decompress(
                    outputPtr.baseAddress,
                    outputSize,
                    inputPtr.baseAddress,
                    data.count
                )
            }
        }
        if ZSTD_isError(result) != 0 {
            let reason = String(cString: ZSTD_getErrorName(result))
            throw ZRLEVideoDecoderError.compressionFailed(reason)
        }
        output.count = result
        return output
    }
    
    func unpackRGB565(_ value: UInt16) -> (r: UInt8, g: UInt8, b: UInt8) {
        let r5 = (value >> 11) & 0x1F
        let g6 = (value >> 5) & 0x3F
        let b5 = value & 0x1F
        let r = UInt8((r5 << 3) | (r5 >> 2))
        let g = UInt8((g6 << 2) | (g6 >> 4))
        let b = UInt8((b5 << 3) | (b5 >> 2))
        return (r, g, b)
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
    
    func readUInt16LE(_ data: Data, offset: inout Int) -> UInt16 {
        let value = data.subdata(in: offset..<(offset + 2)).withUnsafeBytes { $0.load(as: UInt16.self) }.littleEndian
        offset += 2
        return value
    }
    
    func readUInt32LE(_ data: Data, offset: inout Int) -> UInt32 {
        let value = data.subdata(in: offset..<(offset + 4)).withUnsafeBytes { $0.load(as: UInt32.self) }.littleEndian
        offset += 4
        return value
    }
}

private enum ZRLEVideoDecoderError: LocalizedError {
    case compressionFailed(String)
    case invalidTileData(String)
    case pixelBufferUnavailable
    case missingKeyframe
    
    var errorDescription: String? {
        switch self {
        case .compressionFailed(let reason):
            return "ZRLE decompression failed: \(reason)"
        case .invalidTileData(let reason):
            return "ZRLE tile data invalid: \(reason)"
        case .pixelBufferUnavailable:
            return "ZRLE pixel buffer unavailable"
        case .missingKeyframe:
            return "ZRLE missing keyframe"
        }
    }
}
