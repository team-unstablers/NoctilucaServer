import Foundation
import AVFoundation
import CoreImage
import ImageIO
import Metal
import SiriusKit
import UniformTypeIdentifiers
import VideoToolbox

// MARK: - JPEG Compression Mode

/// JPEG 압축 모드.
/// 표준 quality 파라미터 기반 또는 커스텀 양자화 테이블 기반 압축을 선택한다.
private enum JPEGCompressionMode {
    /// 표준 JPEG quality (1-100). libjpeg의 jpeg_set_quality에 매핑된다.
    case quality(Int32)

    /// 커스텀 양자화 테이블 기반 압축.
    case quantizationTables(JPEGQuantizationTables)
}

/// JPEG 커스텀 양자화 테이블 세트.
/// luminance(휘도)와 chrominance(색차) 각각 64개의 양자화 계수를 가진다.
private struct JPEGQuantizationTables {
    /// 휘도(Luminance) 양자화 테이블 (64개 값, natural/raster order)
    let luminance: [UInt32]
    /// 색차(Chrominance) 양자화 테이블 (64개 값, natural/raster order)
    let chrominance: [UInt32]
    /// true면 양자화 값을 baseline JPEG 호환 범위(1-255)로 클램프한다.
    let forceBaseline: Bool

    init(luminance: [UInt32], chrominance: [UInt32], forceBaseline: Bool = true) {
        precondition(luminance.count == 64, "Luminance table must have exactly 64 values")
        precondition(chrominance.count == 64, "Chrominance table must have exactly 64 values")
        self.luminance = luminance
        self.chrominance = chrominance
        self.forceBaseline = forceBaseline
    }
}

extension JPEGQuantizationTables {
    
    /// [Preset 1] UHQ (Ultra High Quality)
    /// 시각적 무손실. 대역폭 소모가 가장 크지만 텍스트가 로컬 화면처럼 쨍합니다.
    static var uhq: JPEGQuantizationTables {
        let q: [UInt32] = Array(repeating: 2, count: 64)
        return JPEGQuantizationTables(luminance: q, chrominance: q)
    }
    
    /// [Preset 2] HQ (High Quality)
    /// 노이즈를 억제하면서 용량을 다이어트합니다. 텍스트 판독이 매우 깔끔합니다.
    static var hq: JPEGQuantizationTables {
        let luma: [UInt32] = [
             8,  8,  8, 10, 12, 14, 16, 16,
             8,  8, 10, 12, 14, 16, 16, 16,
             8, 10, 12, 14, 16, 16, 16, 16,
            10, 12, 14, 16, 16, 16, 16, 16,
            12, 14, 16, 16, 16, 16, 16, 16,
            14, 16, 16, 16, 16, 16, 16, 16,
            16, 16, 16, 16, 16, 16, 16, 16,
            16, 16, 16, 16, 16, 16, 16, 16
        ]
        let chroma = luma.map { min(255, $0 + 4) }
        return JPEGQuantizationTables(luminance: luma, chrominance: chroma)
    }
    
    /// [Preset 3] Standard (기본값 추천)
    /// 표준적인 품질. Quality 50~60 수준의 대역폭을 쓰지만, 텍스트의 가독성에 집중한 형태입니다.
    static var standard: JPEGQuantizationTables {
        let luma: [UInt32] = [
            16, 16, 16, 20, 24, 28, 32, 40,
            16, 16, 20, 24, 28, 32, 40, 48,
            16, 20, 24, 28, 32, 40, 48, 56,
            20, 24, 28, 32, 40, 48, 56, 64,
            24, 28, 32, 40, 48, 56, 64, 64,
            28, 32, 40, 48, 56, 64, 64, 64,
            32, 40, 48, 56, 64, 64, 64, 64,
            40, 48, 56, 64, 64, 64, 64, 64
        ]
        let chroma = luma.map { min(255, $0 + 16) }
        return JPEGQuantizationTables(luminance: luma, chrominance: chroma)
    }
    
    /// [Preset 4] LQ (Low Quality)
    /// 고주파 대역을 강하게 절삭합니다. 글씨가 약간 뭉뚝해지기 시작하지만 대역폭이 크게 감소합니다.
    static var lq: JPEGQuantizationTables {
        let luma: [UInt32] = [
            32,  32,  40,  48,  64,  80, 128, 255,
            32,  40,  48,  64,  80, 128, 255, 255,
            40,  48,  64,  80, 128, 255, 255, 255,
            48,  64,  80, 128, 255, 255, 255, 255,
            64,  80, 128, 255, 255, 255, 255, 255,
            80, 128, 255, 255, 255, 255, 255, 255,
           128, 255, 255, 255, 255, 255, 255, 255,
           255, 255, 255, 255, 255, 255, 255, 255
        ]
        let chroma = luma.map { min(255, $0 + 32) }
        return JPEGQuantizationTables(luminance: luma, chrominance: chroma)
    }
    
    /// [Preset 5] ULQ (Ultra Low Quality)
    /// "화면을 어떻게든 알아볼 수만 있게 전송한다."
    /// 대부분의 주파수 대역을 255(최대 압축)로 밀어버려 대역폭이 극한으로 줄어듭니다.
    static var ulq: JPEGQuantizationTables {
        let luma: [UInt32] = [
             64,  96, 128, 255, 255, 255, 255, 255,
             96, 128, 255, 255, 255, 255, 255, 255,
            128, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255
        ]
        let chroma: [UInt32] = [
            128, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255,
            255, 255, 255, 255, 255, 255, 255, 255
        ]
        return JPEGQuantizationTables(luminance: luma, chrominance: chroma)
    }
}

// MARK: - MJPGVideoEncoder

final class MJPGVideoEncoder: VideoEncoder {
    private let logger = NoctilucaLogger(category: "MJPGVideoEncoder")
    private let workerQueue: DispatchQueue
    private let callbackQueue: DispatchQueue
    private let ciContext: CIContext

    fileprivate var configuration: VideoEncoderConfiguration?

    private var colorFormat: CodecOptionValue = .kColorFormatYUV420
    private var compressMode: JPEGCompressionMode = .quality(90)
    private var quantizeLevel: Int = 0
    private var jpegSubsamplingMode: NJPEGSubsampling = NJPEGSubsampling420
    private var tileSize: Int = 256

    private let maxEncoderFrameRate: Float = 15.0
    private var lastEncodeTime: CFAbsoluteTime = 0

    private var isStarted = false

    let events: AsyncStream<VideoEncoderEvent>
    fileprivate let continuation: AsyncStream<VideoEncoderEvent>.Continuation

    private var frameTiler: FrameTiler!
    private var frameTileDiffer: FrameTileDiffer!

    init() {
        self.workerQueue = DispatchQueue(label: "app.noctiluca.server.projection.encoder.mjpg.worker", qos: .userInitiated)
        self.callbackQueue = DispatchQueue(label: "app.noctiluca.server.projection.encoder.mjpg.callback", qos: .userInitiated)
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
    }

    func prepare(with configuration: VideoEncoderConfiguration) throws {
        guard self.configuration == nil else {
            throw VideoEncoderError.alreadyPrepared
        }

        guard configuration.codec.fourCC == .mjpg else {
            throw VideoEncoderError.unsupportedCodec(configuration.codec.fourCC.stringRepresentation)
        }

        self.configuration = configuration

        // MJPG: kColorFormatAuto는 YUV420과 동일하게 처리
        if let configuredColorFormat = configuration.codec.option(.colorFormat) {
            self.colorFormat = (configuredColorFormat == .kColorFormatAuto) ? .kColorFormatYUV420 : configuredColorFormat
        } else {
            self.colorFormat = .kColorFormatYUV420
        }
        self.jpegSubsamplingMode = (self.colorFormat == .kColorFormatYUV444)
            ? NJPEGSubsampling444
            : NJPEGSubsampling420

        // JPEG quality (1...100)
        let levelString = configuration.codec.option(.compressionLevel)?.rawValue ?? "90"
        if let parsedLevel = Int32(levelString) {
            self.compressMode = .quality(max(1, min(100, parsedLevel)))
        } else {
            self.compressMode = .quality(90)
        }

        // 양자화 레벨 (0...5)
        let quantizeString = configuration.codec.option(.quantizeLevel)?.rawValue ?? "0"
        if let parsedQuantize = Int(quantizeString) {
            self.quantizeLevel = max(0, min(5, parsedQuantize))
        } else {
            self.quantizeLevel = 0
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

        workerQueue.async { [self] in
            guard self.isStarted else { return }

            // 인코더 레벨 프레임 레이트 제한
            let now = CFAbsoluteTimeGetCurrent()
            let minInterval = 1.0 / Double(maxEncoderFrameRate)
            if now - lastEncodeTime < minInterval {
                return
            }
            lastEncodeTime = now

            do {
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

                // 타일 인코딩을 행한다
                let rgbTiles = frameTiler.tile(pixelBuffer)
                guard !rgbTiles.isEmpty else { return }

                // 양자화 적용 (diff 전에 적용하여 동일 타일 증가)
                applyQuantizationToTiles(rgbTiles, quantizeLevel: self.quantizeLevel)

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

                let currentMode = self.compressMode
                for index in diffIndices {
                    let tile = rgbTiles[index]

                    let jpeg = try encodeJPEG(tile, mode: currentMode)

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
            } catch {
                continuation.yield(with: .success(.errorOccurred(error)))
            }
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

    @discardableResult
    func updateQuality(_ quality: Float) -> Bool {
        let clamped = min(max(quality, 0.0), 1.0)
        // 0.0 → 15 (최저), 1.0 → 45 (최고)
        self.compressMode = .quality(Int32(15.0 + clamped * 30.0))
        return true
    }

    @discardableResult
    func updateQuantizeLevel(_ level: Int) -> Bool {
        self.quantizeLevel = max(0, min(5, level))
        return true
    }
}

// MARK: - Helpers

private enum MJPGVideoEncoderError: LocalizedError {
    case compressorUnavailable
    case cgImageCreationFailed
    case destinationCreationFailed
    case destinationFinalizeFailed
    case jpegCompressionFailed(String)

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
        case .jpegCompressionFailed(let message):
            return "JPEG compression failed: \(message)"
        }
    }
}

private extension MJPGVideoEncoder {
    func encodeJPEG(_ pixelBuffer: CVPixelBuffer, mode: JPEGCompressionMode) throws -> Data {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw MJPGVideoEncoderError.compressorUnavailable
        }

        var params = NJPEGCompressParams()
        params.width = Int32(width)
        params.height = Int32(height)
        params.bytesPerRow = Int32(bytesPerRow)
        params.inputBGRA = UnsafePointer(baseAddress.assumingMemoryBound(to: UInt8.self))
        params.subsampling = self.jpegSubsamplingMode

        switch mode {
        case .quality(let quality):
            params.mode = NJPEGCompressModeQuality
            params.quality = quality
            return try compressWithParams(&params)

        case .quantizationTables(let tables):
            params.mode = NJPEGCompressModeQuantTable
            var cTables = NJPEGQuantTables()

            withUnsafeMutablePointer(to: &cTables.luminance) { tuplePtr in
                tuplePtr.withMemoryRebound(to: UInt32.self, capacity: 64) { ptr in
                    for i in 0..<64 {
                        ptr[i] = tables.luminance[i]
                    }
                }
            }
            withUnsafeMutablePointer(to: &cTables.chrominance) { tuplePtr in
                tuplePtr.withMemoryRebound(to: UInt32.self, capacity: 64) { ptr in
                    for i in 0..<64 {
                        ptr[i] = tables.chrominance[i]
                    }
                }
            }
            cTables.forceBaseline = tables.forceBaseline

            return try withUnsafePointer(to: &cTables) { tablesPtr in
                params.quantTables = tablesPtr
                return try compressWithParams(&params)
            }
        }
    }

    func compressWithParams(_ params: inout NJPEGCompressParams) throws -> Data {
        var errorMsg = [CChar](repeating: 0, count: 200)
        let result = njpeg_compress(&params, &errorMsg)

        guard result == 0 else {
            let msg = String(cString: errorMsg)
            throw MJPGVideoEncoderError.jpegCompressionFailed(msg)
        }

        guard let outPtr = params.outBuffer else {
            throw MJPGVideoEncoderError.compressorUnavailable
        }

        let data = Data(bytes: outPtr, count: Int(params.outSize))
        njpeg_free(outPtr)

        return data
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
