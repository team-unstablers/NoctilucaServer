#if !targetEnvironment(simulator)
import Foundation
import CoreMedia
import CoreVideo
import SiriusKitClient

import WebPDecoder

/// WebP 타일 기반 비디오 디코더
final class WebPVideoDecoder: VideoDecoder {
    weak var delegate: VideoDecoderDelegate?
    weak var tileDelegate: TiledVideoDecoderDelegate?

    private let workerQueue: DispatchQueue
    private let callbackQueue: DispatchQueue

    private var configuration: VideoDecoderConfiguration?
    private var isStarted = false

    private var frameWidth: Int = 0
    private var frameHeight: Int = 0

    init() {
        self.workerQueue = DispatchQueue(label: "app.noctiluca.client.projection.decoder.webp.worker")
        self.callbackQueue = DispatchQueue(label: "app.noctiluca.client.projection.decoder.webp.callback")
    }

    init(workerQueue: DispatchQueue, callbackQueue: DispatchQueue) {
        self.workerQueue = workerQueue
        self.callbackQueue = callbackQueue
    }

    func prepare(with configuration: VideoDecoderConfiguration) throws {
        guard self.configuration == nil else {
            throw VideoDecoderError.alreadyPrepared
        }
        guard configuration.codec.fourCC == .webp else {
            throw VideoDecoderError.unsupportedCodec(configuration.codec.fourCC.stringRepresentation)
        }
        self.configuration = configuration

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

private extension WebPVideoDecoder {
    func decodeFrame(_ frame: EncodedFrameInput, decodeStart: DispatchTime) throws {
        let tiles = try decodeTiles(from: frame.data)
        guard tiles.isEmpty == false else {
            throw WebPVideoDecoderError.invalidTileData("empty tile list")
        }

        let isKeyframe = frame.header.flags.contains(.isKeyframe)

        // codec.size가 설정되어 있으면 그것을 사용, 없으면 타일에서 계산 (fallback)
        let targetSize: (width: Int, height: Int)
        if frameWidth > 0, frameHeight > 0 {
            targetSize = (frameWidth, frameHeight)
        } else {
            targetSize = frameSize(from: tiles)
            guard targetSize.width > 0, targetSize.height > 0 else {
                throw WebPVideoDecoderError.invalidTileData("invalid frame size")
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

    func decodeTilesToPixelData(_ tiles: [WebPTile]) throws -> [DecodedTile] {
        var decodedTiles: [DecodedTile] = []
        decodedTiles.reserveCapacity(tiles.count)

        for tile in tiles {
            let pixelData = try decodeWebP(tile)

            decodedTiles.append(DecodedTile(
                rect: CGRect(x: tile.originX, y: tile.originY, width: tile.width, height: tile.height),
                pixelData: pixelData
            ))
        }

        return decodedTiles
    }
}

// MARK: - Tiles

private struct WebPTile {
    let originX: Int
    let originY: Int
    let width: Int
    let height: Int
    let data: Data
}

private extension WebPVideoDecoder {
    func decodeTiles(from data: Data) throws -> [WebPTile] {
        var offset = 0
        guard data.count >= 4 else {
            throw WebPVideoDecoderError.invalidTileData("insufficient header")
        }
        let tileCount = readUInt32BE(data, offset: &offset)
        let maxPossibleTiles = (data.count - 4) / 12
        if Int(tileCount) > maxPossibleTiles {
            throw WebPVideoDecoderError.invalidTileData("tile count exceeds data length")
        }
        if tileCount == 0 { return [] }

        var tiles: [WebPTile] = []
        tiles.reserveCapacity(min(Int(tileCount), maxPossibleTiles))

        for _ in 0..<tileCount {
            guard offset + 12 <= data.count else {
                throw WebPVideoDecoderError.invalidTileData("truncated tile header")
            }
            let x = Int(readUInt16BE(data, offset: &offset))
            let y = Int(readUInt16BE(data, offset: &offset))
            let w = Int(readUInt16BE(data, offset: &offset))
            let h = Int(readUInt16BE(data, offset: &offset))
            let length = Int(readUInt32BE(data, offset: &offset))

            guard length >= 0, length <= data.count - offset else {
                throw WebPVideoDecoderError.invalidTileData("truncated tile payload")
            }
            let tileData = data.subdata(in: offset..<(offset + length))
            offset += length

            tiles.append(WebPTile(originX: x, originY: y, width: w, height: h, data: tileData))
        }

        return tiles
    }
}

// MARK: - Helpers

private extension WebPVideoDecoder {
    func frameSize(from tiles: [WebPTile]) -> (width: Int, height: Int) {
        var maxX = 0
        var maxY = 0
        for tile in tiles {
            maxX = max(maxX, tile.originX + tile.width)
            maxY = max(maxY, tile.originY + tile.height)
        }
        return (maxX, maxY)
    }

    func decodeWebP(_ tile: borrowing WebPTile) throws -> Data {
        let bytesPerPixel = 4  // BGRA
        guard tile.width > 0, tile.height > 0 else {
            throw WebPVideoDecoderError.invalidTileData("invalid tile size")
        }
        guard tile.width <= Int.max / bytesPerPixel else {
            throw WebPVideoDecoderError.invalidTileData("tile width overflow")
        }
        guard tile.height <= Int.max / (tile.width * bytesPerPixel) else {
            throw WebPVideoDecoderError.invalidTileData("tile buffer overflow")
        }
        let stride = tile.width * bytesPerPixel
        let bufferSize = tile.height * stride
        var dstData = Data(count: bufferSize)

        // Advanced API를 사용하여 디코딩 옵션 설정 가능
        var config = WebPDecoderConfig()
        guard WebPInitDecoderConfig(&config) != 0 else {
            throw WebPVideoDecoderError.configInitFailed
        }

        // 디코딩 옵션 설정
        config.options.bypass_filtering = 0       // in-loop 필터링 활성화 (품질 우선)
        config.options.no_fancy_upsampling = 1    // 빠른 업샘플러 사용 (속도 우선)
        config.options.use_threads = 1            // 멀티스레드 디코딩 활성화

        // 출력 버퍼 설정
        config.output.colorspace = MODE_BGRA
        config.output.is_external_memory = 1

        let status = dstData.withUnsafeMutableBytes { dstPtr in
            tile.data.withUnsafeBytes { webpPtr in
                config.output.u.RGBA.rgba = dstPtr.baseAddress?.assumingMemoryBound(to: UInt8.self)
                config.output.u.RGBA.stride = Int32(stride)
                config.output.u.RGBA.size = bufferSize

                return WebPDecode(
                    webpPtr.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    webpPtr.count,
                    &config
                )
            }
        }

        guard status == VP8_STATUS_OK else {
            throw WebPVideoDecoderError.webpDecodeFailed(status)
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

enum WebPVideoDecoderError: LocalizedError {
    case configInitFailed
    case webpDecodeFailed(VP8StatusCode)
    case invalidTileData(String)

    var errorDescription: String? {
        switch self {
        case .configInitFailed:
            return "WebP decoder config initialization failed"
        case .webpDecodeFailed(let status):
            return "WebP decode failed with status: \(status.rawValue)"
        case .invalidTileData(let reason):
            return "WebP tile data invalid: \(reason)"
        }
    }
}
#endif
