import Foundation
import AVFoundation
import SiriusKit

import libzstd

/// ZRLE (RLE + Zstd) 비디오 인코더
final class ZRLEVideoEncoder VideoEncoder {
    private let logger = NoctilucaLogger(category: "ZRLEVideoEncoder")
    private let workerQueue: DispatchQueue
    private let callbackQueue: DispatchQueue

    fileprivate var configuration: VideoEncoderConfiguration?
   
    private var isStarted = false
    
    let events: AsyncStream<VideoEncoderEvent>
    fileprivate let continuation: AsyncStream<VideoEncoderEvent>.Continuation
    
    let frameTiler = FrameTiler(tileSize: 64)
    let frameTileDiffer = FrameTileDiffer()
    
    override init() {
        self.workerQueue = DispatchQueue(label: "tech.unstablers.noctiluca.zrleencoder.worker")
        self.callbackQueue = DispatchQueue(label: "tech.unstablers.noctiluca.zrleencoder.callback")
        
        var continuationLocal: AsyncStream<VideoEncoderEvent>.Continuation!
        
        self.events = AsyncStream<VideoEncoderEvent>(VideoEncoderEvent.self, bufferingPolicy: .unbounded) { continuation in
            continuationLocal = continuation
        }
        
        self.continuation = continuationLocal
    }
    
    init(workerQueue: DispatchQueue, callbackQueue: DispatchQueue) {
        self.workerQueue = DispatchQueue(label: "tech.unstablers.noctiluca.zrleencoder.worker")
        self.callbackQueue = DispatchQueue(label: "tech.unstablers.noctiluca.zrleencoder.callback")
        
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
        let colorFormat = configuration.codec.option(.colorFormat)
        // Zstd compression level
        let compressionLevel = configuration.codec.option(.compressionLevel)
        
        // TODO: ...
        
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
        // TODO:
        
        // RGB888 or RGB565
        let rgbSampleBuffer = try sampleBuffer.convertToRGBIfNeeded(required: self.configuration?.codec.option(.colorFormat))
        
        guard let pixelBuffer = rgbSampleBuffer.imageBuffer else {
            throw VideoEncoderError.invalidSampleBuffer
        }
        
        // 64x64로 타일 인코딩을 행한다
        let rgbTiles = frameTiler.tile(pixelBuffer)
        // 기존 프레임과의 diff를 행한다
        let diffIndices = frameTileDiffer.feed(rgbTiles)
        
        // 변경된 각 타일에 대해 RLE 압축을 수행한 뒤, Zstd로 다시 압축한다
        // TODO: 가능한 경우 병렬 처리를 행한다
        
        var encodedTiles: [ProjectionFrameTile] = []
        encodedTiles.reserveCapacity(diffIndices.count)
        
        for index in diffIndices {
            let tile = rgbTiles[index]
            let rle = self.rleCompress(tile)
            let zstd = self.zstdCompress(rle, compressionLevel: self.configuration?.codec.option(.compressionLevel))
            
            // 헉, 잠깐만! 이거 지오메트리 얻으려면 frameTileDiffer에서 타일 위치도 알아야 하는 거 아냐?
            let geometry = CGRect(...)
            
            encodedTiles.append(ProjectionFrameTile(geometry: geometry, data: zstd))
        }
        
        // emit frame
        // see SiriusKit/channel/msgdef/v1/channels/projection_data/TiledFrame.swift
        
        let frameData = ProjectionFrameTile.encode(encodedTiles)
        let frameHeader = FrameDataHeader(
            frameID: ...,
            frameLength: UInt32(frameData.count),
            presentationTimestamp: ..., // TODO: mach_absolute_time(),
            flags: [.isKeyframe]
        )
        let frame = EncodedFrame(header: consume frameHeader, data: consume frameData, formatDescription: nil)
        encoder.continuation.yield(with: .success(.frameEncoded(consume frame)))
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

