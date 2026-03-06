import Foundation
import CoreMedia
import CoreVideo
import SiriusKitClient

import libturbojpeg

/// MJPG (tiled JPEG) 소프트웨어 디코더
final class MJPGVideoDecoder: VideoDecoder {
    weak var delegate: VideoDecoderDelegate?
    weak var tileDelegate: TiledVideoDecoderDelegate?

    private let workerQueue: DispatchQueue
    private let callbackQueue: DispatchQueue

    private var configuration: VideoDecoderConfiguration?
    private var isStarted = false

    private var frameWidth: Int = 0
    private var frameHeight: Int = 0

    private var decompressHandle: tjhandle? = nil
    
    init() {
        self.workerQueue = DispatchQueue(label: "app.noctiluca.client.projection.decoder.mjpg.worker")
        self.callbackQueue = DispatchQueue(label: "app.noctiluca.client.projection.decoder.mjpg.callback")
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
        guard self.decompressHandle != nil else {
            throw MJPGVideoDecoderError.decompressorUnavailable
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

private extension MJPGVideoDecoder {
    func decodeFrame(_ frame: EncodedFrameInput, decodeStart: DispatchTime) throws {
        let tiles = try decodeTiles(from: frame.data)
        guard tiles.isEmpty == false else {
            throw MJPGVideoDecoderError.invalidTileData("empty tile list")
        }

        let isKeyframe = frame.header.flags.contains(.isKeyframe)

        // codec.size가 설정되어 있으면 그것을 사용, 없으면 타일에서 계산 (fallback)
        let targetSize: (width: Int, height: Int)
        if frameWidth > 0, frameHeight > 0 {
            targetSize = (frameWidth, frameHeight)
        } else {
            targetSize = frameSize(from: tiles)
            guard targetSize.width > 0, targetSize.height > 0 else {
                throw MJPGVideoDecoderError.invalidTileData("invalid frame size")
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

    func decodeTilesToPixelData(_ tiles: [MJPGTile]) throws -> [DecodedTile] {
        let count = tiles.count
        let results = UnsafeMutableBufferPointer<DecodedTile?>.allocate(capacity: count)
        results.initialize(repeating: nil)
        defer { results.deallocate() }

        var firstError: Error?
        let errorLock = NSLock()

        DispatchQueue.concurrentPerform(iterations: count) { index in
            // tjhandle은 thread-safe가 아니므로 이터레이션마다 독립 핸들 생성
            guard let handle = tjInitDecompress() else {
                errorLock.withLock {
                    if firstError == nil { firstError = MJPGVideoDecoderError.decompressorUnavailable }
                }
                return
            }
            defer { tjDestroy(handle) }

            do {
                let tile = tiles[index]
                let pixelData = try decodeJPEG(tile, handle: handle)
                results[index] = DecodedTile(
                    rect: CGRect(x: tile.originX, y: tile.originY, width: tile.width, height: tile.height),
                    pixelData: pixelData
                )
            } catch {
                errorLock.withLock {
                    if firstError == nil { firstError = error }
                }
            }
        }

        if let error = firstError { throw error }
        return results.compactMap { $0 }
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
        let maxPossibleTiles = (data.count - 4) / 12
        if Int(tileCount) > maxPossibleTiles {
            throw MJPGVideoDecoderError.invalidTileData("tile count exceeds data length")
        }
        if tileCount == 0 { return [] }

        var tiles: [MJPGTile] = []
        tiles.reserveCapacity(min(Int(tileCount), maxPossibleTiles))

        for _ in 0..<tileCount {
            guard offset + 12 <= data.count else {
                throw MJPGVideoDecoderError.invalidTileData("truncated tile header")
            }
            let x = Int(readUInt16BE(data, offset: &offset))
            let y = Int(readUInt16BE(data, offset: &offset))
            let w = Int(readUInt16BE(data, offset: &offset))
            let h = Int(readUInt16BE(data, offset: &offset))
            let length = Int(readUInt32BE(data, offset: &offset))

            guard length >= 0, length <= data.count - offset else {
                throw MJPGVideoDecoderError.invalidTileData("truncated tile payload")
            }
            let tileData = data.subdata(in: offset..<(offset + length))
            offset += length

            tiles.append(MJPGTile(originX: x, originY: y, width: w, height: h, data: tileData))
        }

        return tiles
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
    
    func decodeJPEG(_ tile: borrowing MJPGTile, handle: tjhandle? = nil) throws -> Data {
        let bytesPerPixel = 4
        guard tile.width > 0, tile.height > 0 else {
            throw MJPGVideoDecoderError.invalidTileData("invalid tile size")
        }
        guard tile.width <= Int.max / bytesPerPixel else {
            throw MJPGVideoDecoderError.invalidTileData("tile width overflow")
        }
        guard tile.height <= Int.max / (tile.width * bytesPerPixel) else {
            throw MJPGVideoDecoderError.invalidTileData("tile buffer overflow")
        }
        let bufferSize = tile.width * tile.height * bytesPerPixel
        var dstData = Data(count: bufferSize)

        guard let resolvedHandle = handle ?? self.decompressHandle else {
            throw MJPGVideoDecoderError.decompressorUnavailable
        }

        let retval = dstData.withUnsafeMutableBytes { dstPtr in
            tile.data.withUnsafeBytes { jpegPtr in
                tjDecompress2(
                    resolvedHandle,
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
    case decompressorUnavailable
    case jpegDecodeFailed
    case invalidTileData(String)
    case pixelBufferUnavailable
    case missingKeyframe
    
    var errorDescription: String? {
        switch self {
        case .decompressorUnavailable:
            return "MJPG decompressor is not available"
        case .jpegDecodeFailed:
            return "MJPG JPEG decode failed"
        case .invalidTileData(let reason):
            return "MJPG tile data invalid: \(reason)"
        case .pixelBufferUnavailable:
            return "MJPG pixel buffer unavailable"
        case .missingKeyframe:
            return "MJPG missing keyframe"
        }
    }
}
