import Foundation
import CoreMedia
import CoreVideo
import SiriusKitClient

import libzstd

/// ZRLE (RLE + Zstd) 소프트웨어 디코더
final class ZRLEVideoDecoder: VideoDecoder {
    weak var delegate: VideoDecoderDelegate?
    weak var tileDelegate: TiledVideoDecoderDelegate?

    private let workerQueue: DispatchQueue
    private let callbackQueue: DispatchQueue

    private var configuration: VideoDecoderConfiguration?
    private var isStarted = false
    private var colorFormat: CodecOptionValue = .kColorFormatRGB888

    private var frameWidth: Int = 0
    private var frameHeight: Int = 0
    
    init() {
        self.workerQueue = DispatchQueue(label: "app.noctiluca.client.projection.decoder.zrle.worker")
        self.callbackQueue = DispatchQueue(label: "app.noctiluca.client.projection.decoder.zrle.callback")
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

        // codec.size에서 실제 콘텐츠 크기 설정
        if let size = configuration.codec.size {
            self.frameWidth = Int(size.width)
            self.frameHeight = Int(size.height)
        }
    }
    
    func start() throws {
        guard configuration != nil else { throw VideoDecoderError.notPrepared }
        isStarted = true
    }
    
    func stop() throws {
        workerQueue.sync {
            frameWidth = 0
            frameHeight = 0
            isStarted = false
        }
    }

    func flush() throws {
        // Compositor handles base frame state now
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

        // codec.size가 설정되어 있으면 그것을 사용, 없으면 타일에서 계산 (fallback)
        let targetSize: (width: Int, height: Int)
        if frameWidth > 0, frameHeight > 0 {
            targetSize = (frameWidth, frameHeight)
        } else {
            targetSize = frameSize(from: tiles)
            guard targetSize.width > 0, targetSize.height > 0 else {
                throw ZRLEVideoDecoderError.invalidTileData("invalid frame size")
            }
            frameWidth = targetSize.width
            frameHeight = targetSize.height
        }

        let decodedTiles = try decodeTilesToPixelData(tiles)

        let pts = CMTime(value: CMTimeValue(frame.header.presentationTimestamp), timescale: 1_000_000)
        let decodeEnd = DispatchTime.now()
        let decodeMs = max(0, Double(decodeEnd.uptimeNanoseconds - decodeStart.uptimeNanoseconds) / 1_000_000.0)

        let tileFrame = DecodedTileFrame(
            tiles: decodedTiles,
            pts: pts,
            isKeyFrame: isKeyframe,
            frameSize: CGSize(width: targetSize.width, height: targetSize.height),
            decodeTimeMs: decodeMs
        )

        callbackQueue.async {
            self.tileDelegate?.tiledVideoDecoder(self, didDecode: tileFrame)
        }
    }

    func decodeTilesToPixelData(_ tiles: [ZRLETile]) throws -> [DecodedTile] {
        var decodedTiles: [DecodedTile] = []
        decodedTiles.reserveCapacity(tiles.count)

        for tile in tiles {
            let rleData = try zstdDecompress(tile.data)
            let pixelData = try rleDecompressToData(
                rleData,
                width: tile.width,
                height: tile.height,
                colorFormat: colorFormat
            )

            decodedTiles.append(DecodedTile(
                rect: CGRect(x: tile.originX, y: tile.originY, width: tile.width, height: tile.height),
                pixelData: pixelData
            ))
        }

        return decodedTiles
    }

    func rleDecompressToData(
        _ data: Data,
        width: Int,
        height: Int,
        colorFormat: CodecOptionValue
    ) throws -> Data {
        let bytesPerPixel = 4  // BGRA
        let bytesPerRow = width * bytesPerPixel
        var output = Data(count: bytesPerRow * height)

        try output.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress else {
                throw ZRLEVideoDecoderError.pixelBufferUnavailable
            }
            try rleDecompress(
                data,
                to: baseAddress.assumingMemoryBound(to: UInt8.self),
                bytesPerRow: bytesPerRow,
                originX: 0,
                originY: 0,
                width: width,
                height: height,
                colorFormat: colorFormat
            )
        }

        return output
    }
}

// MARK: - Tiles

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

enum ZRLEVideoDecoderError: LocalizedError {
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
