//
//  ProjectionSession.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Darwin

import Foundation
import Combine
import Atomics

import CoreGraphics
import CoreMedia

import AVFoundation
import Metal

import SiriusKitClient

enum ProjectionSessionError: Error {
    case codecSizeUnavailable
}

enum ProjectionSessionEvent: Sendable {
    /// 프로젝션이 시작되었습니다.
    case projectionStarted
    
    /// 프로젝션이 중지될 예정입니다.
    case projectionWillStop
    
    /// 프로젝션이 중지되었습니다.
    // TODO: 이거 reason 있어야 하지 않아?
    case projectionStopped
    
    /// 오류가 발생했습니다.
    /// - Parameters:
    ///  - error: 발생한 오류
    ///  - fatal: 치명적인 오류인지 여부
    case errorOccurred(Error, fatal: Bool)
    
    /// 성능 보고서를 발행하였습니다.
    case performanceReportEmitted(ProjectionPerformanceReport)
    
    case sizeChanged(CGSize)

    /// 서버로부터 DegradationNotice를 수신하였습니다.
    case degradationNoticeReceived(DegradationNotice)

    /// 코덱 구성이 변경되었습니다 (디코더 교체, 렌더링 경로 변경 등).
    /// `isTiledCodec`이 true이면 Metal 캔버스 직접 렌더링을 사용해야 합니다.
    case codecConfigured(isTiledCodec: Bool)
}

class ProjectionSession: Identifiable {
    private let logger = NoctilucaLogger(category: "ProjectionSession")

    let id: UUID
    let dataChannel: ProjectionDataChannel
    weak var controlChannel: ProjectionChannel?

    private(set) var decoder: (any VideoDecoder)?
    private var tileCompositor: TileCompositor?

    private var performanceReporter: ProjectionPerformanceReporter?

    private let enableJitterBuffer: Bool
    private let jitterBufferPreset: AppSettings.JitterBufferPreset
    private var jitterBuffer: VideoJitterBuffer?

    let displayID: Int

    private var displayLayersLock = NSLock()
    private var displayLayers: [ObjectIdentifier: AVSampleBufferDisplayLayer] = [:]

    nonisolated func registerDisplayLayer(_ layer: AVSampleBufferDisplayLayer) {
        displayLayersLock.withLock {
            displayLayers[ObjectIdentifier(layer)] = layer
        }
    }

    nonisolated func unregisterDisplayLayer(_ layer: AVSampleBufferDisplayLayer) {
        displayLayersLock.withLock {
            displayLayers.removeValue(forKey: ObjectIdentifier(layer))
        }
    }

    nonisolated private func enqueueToAllDisplayLayers(_ sampleBuffer: CMSampleBuffer) {
        displayLayersLock.withLock {
            for layer in displayLayers.values {
                layer.enqueue(sampleBuffer)
            }
        }
    }

    // MARK: - Metal Video Renderer Management (VT 코덱 직접 렌더링)

    private var metalVideoRenderersLock = NSLock()
    private var metalVideoRenderers: [ObjectIdentifier: MetalVideoRenderer] = [:]

    nonisolated func registerMetalVideoRenderer(_ renderer: MetalVideoRenderer) {
        metalVideoRenderersLock.withLock {
            metalVideoRenderers[ObjectIdentifier(renderer)] = renderer
        }
        // 이미 코덱이 설정되어 있으면 즉시 메타데이터 전달
        if let codec {
            renderer.updateCodecMetadata(codec: codec)
        }
    }

    nonisolated func unregisterMetalVideoRenderer(_ renderer: MetalVideoRenderer) {
        metalVideoRenderersLock.withLock {
            metalVideoRenderers.removeValue(forKey: ObjectIdentifier(renderer))
        }
    }

    /// Metal 비디오 렌더러가 등록되어 있는지 여부
    private var hasMetalVideoRenderers: Bool {
        metalVideoRenderersLock.withLock {
            !metalVideoRenderers.isEmpty
        }
    }

    /// 모든 Metal 비디오 렌더러에 CVPixelBuffer를 제출한다.
    nonisolated private func presentToAllMetalVideoRenderers(_ pixelBuffer: CVPixelBuffer) {
        metalVideoRenderersLock.withLock {
            for renderer in metalVideoRenderers.values {
                renderer.present(pixelBuffer)
            }
        }
    }

    // MARK: - Canvas Renderer Management (Metal 직접 렌더링)

    private var canvasRenderersLock = NSLock()
    private var canvasRenderers: [ObjectIdentifier: ProjectionCanvasRenderer] = [:]

    nonisolated func registerCanvasRenderer(_ renderer: ProjectionCanvasRenderer) {
        canvasRenderersLock.withLock {
            canvasRenderers[ObjectIdentifier(renderer)] = renderer
        }
        // 이미 캔버스가 있으면 즉시 연결
        if let canvasCompositor = tileCompositor as? CanvasTileCompositor {
            renderer.canvasTexture = canvasCompositor.canvasTexture
        }
    }

    nonisolated func unregisterCanvasRenderer(_ renderer: ProjectionCanvasRenderer) {
        canvasRenderersLock.withLock {
            canvasRenderers.removeValue(forKey: ObjectIdentifier(renderer))
        }
    }

    /// 모든 캔버스 렌더러에 다시 그리기를 요청한다.
    nonisolated private func notifyAllCanvasRenderers() {
        canvasRenderersLock.withLock {
            for renderer in canvasRenderers.values {
                renderer.setNeedsDisplay()
            }
        }
    }

    /// 캔버스 텍스처가 변경되었을 때 (리사이즈 등) 모든 렌더러에 새 텍스처를 전달한다.
    nonisolated private func updateCanvasTextureForAllRenderers(_ texture: MTLTexture?) {
        canvasRenderersLock.withLock {
            for renderer in canvasRenderers.values {
                renderer.canvasTexture = texture
            }
        }
    }

    /// 현재 입력 데이터 레이트 (bytes per second)
    let currentDataRate = ManagedAtomic<Int>(0)

    /// 현재 입력 데이터 레이트 (Kbps)
    var currentDataRateKbps: Double {
        Double(currentDataRate.load(ordering: .relaxed)) * 8.0 / 1000.0
    }

    var decoderTypeName: String {
        guard let decoder else { return "N/A" }
        switch decoder {
        case let vtDecoder as VTVideoDecoder: return vtDecoder.decoderTypeName
        case is ZRLEVideoDecoder: return "ZRLE"
#if !targetEnvironment(simulator)
        case is WebPVideoDecoder: return "WebP"
#endif
        case is MJPGVideoDecoder: return "MJPG"
        default: return "Unknown"
        }
    }

    private(set) var codec: Codec?
    var formatDescription: CMFormatDescription?

    var size: CGSize = .zero {
        didSet {
            if oldValue != size {
                Task { @MainActor in
                    events.send(.sizeChanged(size))
                }
            }
        }
    }
    
    let events = PassthroughSubject<ProjectionSessionEvent, Never>()

    @MainActor
    init(id: UUID, displayID: Int, dataChannel: ProjectionDataChannel, controlChannel: ProjectionChannel, enableJitterBuffer: Bool = false, jitterBufferPreset: AppSettings.JitterBufferPreset = .lowLatency) {
        self.id = id
        self.displayID = displayID

        self.dataChannel = dataChannel
        self.controlChannel = controlChannel
        self.enableJitterBuffer = enableJitterBuffer
        self.jitterBufferPreset = jitterBufferPreset

        self.decoder = VTVideoDecoder()
        self.performanceReporter = ProjectionPerformanceReporter(sessionID: id, parent: self)

        if enableJitterBuffer {
            let buffer = VideoJitterBuffer(preset: jitterBufferPreset.bufferPreset)
            buffer.onFrameReady = { [weak self] sampleBuffer in
                self?.enqueueToAllDisplayLayers(sampleBuffer)
            }
            self.jitterBuffer = buffer
            logger.info("Jitter buffer enabled for session \(id) (preset: \(jitterBufferPreset.rawValue))")
        }

        self.dataChannel.delegate = self
        self.dataChannel.activate()
        self.decoder?.delegate = self
    }

    deinit {
        jitterBuffer?.stop()
        tileCompositor?.invalidate()
        try? decoder?.stop()
    }

    func prepare(codec: Codec) async throws {
        guard let size = codec.size else {
            throw ProjectionSessionError.codecSizeUnavailable
        }
        self.codec = codec
        self.size  = size.cgSize

        // 기존 디코더 정리 (새 디코더로 교체 전)
        try? decoder?.stop()
        tileCompositor?.invalidate()
        tileCompositor = nil

        switch codec.fourCC {
        case .zrle:
            let zrleDecoder = ZRLEVideoDecoder()
            zrleDecoder.delegate = self
            zrleDecoder.tileDelegate = self
            decoder = zrleDecoder
            tileCompositor = createTileCompositor(frameSize: size.cgSize)
            formatDescription = nil

        case .mjpg:
            let mjpgDecoder = MJPGVideoDecoder()
            mjpgDecoder.delegate = self
            mjpgDecoder.tileDelegate = self
            decoder = mjpgDecoder
            tileCompositor = createTileCompositor(frameSize: size.cgSize)
            formatDescription = nil

#if !targetEnvironment(simulator)
        case .webp:
            let webpDecoder = WebPVideoDecoder()
            webpDecoder.delegate = self
            webpDecoder.tileDelegate = self
            decoder = webpDecoder
            tileCompositor = createTileCompositor(frameSize: size.cgSize)
            formatDescription = nil
#endif

        default:
            decoder = VTVideoDecoder()
            decoder?.delegate = self
            tileCompositor = nil
        }
        try decoder?.prepare(with: .init(codec: codec))

        let isTiled = tileCompositor != nil

        // VT 코덱인 경우 Metal 비디오 렌더러에 코덱 메타데이터 전달
        if !isTiled {
            metalVideoRenderersLock.withLock {
                for renderer in metalVideoRenderers.values {
                    renderer.updateCodecMetadata(codec: codec)
                }
            }
        }

        Task { @MainActor in
            events.send(.codecConfigured(isTiledCodec: isTiled))
        }
    }
    
    /// 서버로부터 코덱/해상도 변경 통지를 받았을 때 디코더를 재구성합니다.
    func reconfigure(codec: Codec) async throws {
        logger.info("Reconfiguring session \(self.id) with new codec: \(codec.fourCC)")

        let previousSize = self.size
        try await prepare(codec: codec)

        if let newSize = codec.size?.cgSize, newSize != previousSize {
            Task { @MainActor in
                self.events.send(.sizeChanged(newSize))
            }
        }
    }

    func start() async throws {
        do {
            try self.decoder?.start()
            self.jitterBuffer?.start()
            await self.performanceReporter?.start()

            await MainActor.run {
                self.events.send(.projectionStarted)
            }
        } catch {
            await MainActor.run {
                self.events.send(.errorOccurred(error, fatal: true))
            }

            throw error
        }
    }
    
    func stop(sendStopRequest: Bool = true) async throws {
        await MainActor.run {
            self.events.send(.projectionWillStop)
        }

        self.jitterBuffer?.stop()
        await self.performanceReporter?.stop()
        try self.decoder?.stop()

        if sendStopRequest, let controlChannel = self.controlChannel {
            let sessionID = self.id
            let logger = self.logger
            Task { [weak controlChannel] in
                do {
                    try await controlChannel?.send(
                        opcode: .stopProjectionRequest,
                        message: StopProjectionRequest(identifier: sessionID)
                    )
                } catch {
                    logger.warning("Failed to send StopProjectionRequest for session \(sessionID): \(error)")
                }
            }
        }

        await MainActor.run {
            self.events.send(.projectionStopped)
        }

        try? await self.dataChannel.close()
    }
}


extension ProjectionSession: ProjectionDataChannelDelegate {
    func projectionDataChannel(_ channel: ProjectionDataChannel, didReceiveCodecParameterSets codecParameterSets: consuming SiriusKitClient.CodecParameterSetMessage) {
        guard let codec = self.codec?.fourCC else { return }
        
        do {
            switch codec {
            case .hvc1:
                self.formatDescription = try CMFormatDescription(hevcParameterSets: codecParameterSets.parameterSets.map { $0.data })
                
            case .avc1:
                self.formatDescription = try CMFormatDescription(h264ParameterSets: codecParameterSets.parameterSets.map { $0.data })
                
            case .zrle:
                return
            default:
                return
            }
        } catch {
            logger.error("Failed to create format description: \(error.localizedDescription)")
            Task { @MainActor in
                // 다음 키프레임을 받으면 되므로 fatal까진 아님
                self.events.send(.errorOccurred(error, fatal: false))
            }
        }
    }
    
    func projectionDataChannel(_ channel: ProjectionDataChannel, didReceiveDegradationNotice notice: DegradationNotice) {
        Task { @MainActor in
            self.events.send(.degradationNoticeReceived(notice))
        }
    }

    func projectionDataChannel(_ channel: ProjectionDataChannel, didReceiveFrame frame: consuming EncodedFrameInput) {
        self.performanceReporter?.recordReceivedFrame(byteCount: frame.data.count)
        do {
            var header = frame.header
            var frameData = frame.data
            var formatDesc = self.formatDescription

            // Annex-B 형식 프레임: SPS/PPS/VPS를 추출하고 AVCC로 변환
            if let codec = self.codec?.fourCC,
               frame.header.flags.contains(.H264_HEVC_isAnnexBFormatted) {
                let parsed = AnnexBParser.parse(frame.data, codec: codec)

                if !parsed.parameterSets.isEmpty {
                    do {
                        switch codec {
                        case .hvc1:
                            formatDesc = try CMFormatDescription(hevcParameterSets: parsed.parameterSets)
                        case .avc1:
                            formatDesc = try CMFormatDescription(h264ParameterSets: parsed.parameterSets)
                        default:
                            break
                        }
                        self.formatDescription = formatDesc
                    } catch {
                        logger.error("Failed to create format description from Annex-B parameter sets: \(error.localizedDescription)")
                    }
                }

                frameData = parsed.videoData
                header = FrameDataHeader(
                    frameID: frame.header.frameID,
                    frameLength: UInt32(parsed.videoData.count),
                    presentationTimestamp: frame.header.presentationTimestamp,
                    flags: frame.header.flags
                )
            }

            try self.decoder?.decode(EncodedFrameInput(
                header: header,
                data: frameData,
                formatDescription: formatDesc
            ))
        } catch {
            logger.error("decoder decode error: \(error.localizedDescription)")
            Task { @MainActor in
                // 대부분의 경우 다음 키프레임을 받으면 되므로 fatal까진 아님
                self.events.send(.errorOccurred(error, fatal: false))
            }

            self.performanceReporter?.recordDroppedFrame()
        }
    }
}


extension ProjectionSession: VideoDecoderDelegate {
    func videoDecoder(_ decoder: any VideoDecoder, didDecode frame: DecodedFrame) {
        self.performanceReporter?.recordDecodedFrame(decodeTimeMs: frame.decodeTimeMs)

        // Metal 비디오 렌더러가 등록되어 있으면 CVPixelBuffer를 직접 전달
        if hasMetalVideoRenderers {
            presentToAllMetalVideoRenderers(frame.pixelBuffer)
            return
        }

        // Fallback: AVSampleBufferDisplayLayer 경로
        if let jitterBuffer {
            jitterBuffer.enqueue(pixelBuffer: frame.pixelBuffer, remotePTS: frame.pts.seconds)
        } else {
            let now = mach_absolute_time()
            let presentationTime = CMTimeMake(value: Int64(now), timescale: 1_000_000_000)

            do {
                let sampleBuffer = try CMSampleBuffer(
                    imageBuffer: frame.pixelBuffer,
                    formatDescription: CMFormatDescription(imageBuffer: frame.pixelBuffer),
                    sampleTiming: CMSampleTimingInfo(
                        duration: CMTime.invalid,
                        presentationTimeStamp: presentationTime,
                        decodeTimeStamp: CMTime.invalid
                    )
                )

                enqueueToAllDisplayLayers(sampleBuffer)
            } catch {
                logger.error("Failed to create CMSampleBuffer: \(error.localizedDescription)")
                performanceReporter?.recordDroppedFrame()
            }
        }
    }
    
    func videoDecoder(_ decoder: any VideoDecoder, didFailWith error: any Error) {
        logger.error("decoder error: \(error.localizedDescription)")
        Task { @MainActor in
            self.events.send(.errorOccurred(error, fatal: false))
        }
    }
    
    func videoDecoder(_ decoder: any VideoDecoder, didDropFrameWithID frameID: UInt64, reason: String) {
        logger.error("dropped frame ID: \(frameID), reason: \(reason)")
        self.performanceReporter?.recordDroppedFrame()
    }
}

extension ProjectionSession: TiledVideoDecoderDelegate {
    func tiledVideoDecoder(_ decoder: any VideoDecoder, didDecode frame: DecodedTileFrame) {
        guard let compositor = tileCompositor else {
            logger.error("Tile compositor not available for tile frame")
            performanceReporter?.recordDroppedFrame()
            return
        }

        do {
            if size == .zero {
                size = frame.frameSize
            }

            // Metal 캔버스 직접 렌더링 경로:
            // CanvasTileCompositor인 경우 캔버스만 업데이트하고
            // 등록된 MetalProjectionView에 다시 그리기를 요청한다.
            // CVPixelBuffer → CMSampleBuffer → AVSampleBufferDisplayLayer 경유를 제거.
            if let canvasCompositor = compositor as? CanvasTileCompositor {
                try canvasCompositor.compositeToCanvas(frame)
                performanceReporter?.recordDecodedFrame(decodeTimeMs: frame.decodeTimeMs)

                // 캔버스 텍스처가 변경되었을 수 있음 (리사이즈)
                updateCanvasTextureForAllRenderers(canvasCompositor.canvasTexture)
                notifyAllCanvasRenderers()
                return
            }

            // Legacy 경로: CVPixelBuffer → CMSampleBuffer → AVSampleBufferDisplayLayer
            let pixelBuffer = try compositor.composite(frame)
            performanceReporter?.recordDecodedFrame(decodeTimeMs: frame.decodeTimeMs)

            if let jitterBuffer {
                jitterBuffer.enqueue(pixelBuffer: pixelBuffer, remotePTS: frame.pts.seconds)
            } else {
                let now = mach_absolute_time()
                let presentationTime = CMTimeMake(value: Int64(now), timescale: 1_000_000_000)

                let sampleBuffer = try CMSampleBuffer(
                    imageBuffer: pixelBuffer,
                    formatDescription: CMFormatDescription(imageBuffer: pixelBuffer),
                    sampleTiming: CMSampleTimingInfo(
                        duration: CMTime.invalid,
                        presentationTimeStamp: presentationTime,
                        decodeTimeStamp: CMTime.invalid
                    )
                )

                enqueueToAllDisplayLayers(sampleBuffer)
            }
        } catch {
            logger.error("Tile composition failed: \(error.localizedDescription)")
            Task { @MainActor in
                self.events.send(.errorOccurred(error, fatal: false))
            }

            performanceReporter?.recordDroppedFrame()
        }
    }
}

private actor ProjectionPerformanceReporter {
    private let logger = SiriusLogger(category: "ProjectionPerformanceReporter", subsystem: "app.noctiluca.client")
    private let sessionID: UUID

    private weak var parent: ProjectionSession?

    private var controlChannel: ProjectionChannel? {
        parent?.controlChannel
    }

    // atomic 카운터 — nonisolated 메서드에서 lock-free로 접근
    private let _received = ManagedAtomic<UInt32>(0)
    private let _decoded = ManagedAtomic<UInt32>(0)
    private let _dropped = ManagedAtomic<UInt32>(0)
    private let _decodeTimeSumUs = ManagedAtomic<UInt64>(0)
    private let _receivedBytes = ManagedAtomic<UInt64>(0)

    private var timerTask: Task<Void, Never>?

    init(sessionID: UUID, parent: ProjectionSession) {
        self.sessionID = sessionID
        self.parent = parent
    }

    // MARK: - Lifecycle

    func start() {
        guard timerTask == nil else { return }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self else { return }
                await self.flush()
            }
        }
    }

    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Hot-path recording (nonisolated, lock-free)

    nonisolated func recordReceivedFrame(byteCount: Int) {
        _received.wrappingIncrement(ordering: .relaxed)
        _receivedBytes.wrappingIncrement(by: UInt64(byteCount), ordering: .relaxed)
    }

    nonisolated func recordDecodedFrame(decodeTimeMs: Double) {
        _decoded.wrappingIncrement(ordering: .relaxed)
        _decodeTimeSumUs.wrappingIncrement(
            by: UInt64((decodeTimeMs * 1000).rounded()),
            ordering: .relaxed
        )
    }

    nonisolated func recordDroppedFrame() {
        _dropped.wrappingIncrement(ordering: .relaxed)
    }

    // MARK: - Flush

    private nonisolated func snapshotAndReset() -> (received: UInt32, decoded: UInt32, dropped: UInt32, avgDecodeMs: UInt32, bytes: UInt64) {
        let received = _received.exchange(0, ordering: .relaxed)
        let decoded = _decoded.exchange(0, ordering: .relaxed)
        let dropped = _dropped.exchange(0, ordering: .relaxed)
        let decodeTimeSumUs = _decodeTimeSumUs.exchange(0, ordering: .relaxed)
        let receivedBytes = _receivedBytes.exchange(0, ordering: .relaxed)

        let avgDecodeMs: UInt32 = decoded > 0
            ? UInt32((Double(decodeTimeSumUs) / 1000.0 / Double(decoded)).rounded())
            : 0

        return (received, decoded, dropped, avgDecodeMs, receivedBytes)
    }

    private func flush() async {
        guard let controlChannel else { return }
        let snapshot = snapshotAndReset()

        // 1초 간격 flush이므로 bytes == bytes/sec
        parent?.currentDataRate.store(Int(snapshot.bytes), ordering: .relaxed)

        if snapshot.received == 0 && snapshot.decoded == 0 && snapshot.dropped == 0 {
            return
        }

        let report = ProjectionPerformanceReport(
            identifier: sessionID,
            receivedFrameCount: snapshot.received,
            decodedFrameCount: snapshot.decoded,
            droppedFrameCount: snapshot.dropped,
            averageDecodeTimeMs: snapshot.avgDecodeMs
        )

        Task { @MainActor [parent] in
            parent?.events.send(.performanceReportEmitted(report))
        }

        do {
            logger.info("Sending performance report for session \(self.sessionID): received=\(snapshot.received), decoded=\(snapshot.decoded), dropped=\(snapshot.dropped), avgDecodeMs=\(snapshot.avgDecodeMs)")
            try await controlChannel.send(opcode: .projectionPerformanceReport, message: report)
        } catch {
            logger.warning("Failed to send performance report for session \(self.sessionID): \(error)")
        }
    }
}

private extension ProjectionSession {
    func createTileCompositor(frameSize: CGSize) -> TileCompositor {
        // Metal 가능하면 MetalTileCompositor 사용, 실패 시 CPU fallback
        if let metalCompositor = try? MetalTileCompositor(frameSize: frameSize) {
            logger.info("Using MetalTileCompositor for tile composition")
            return metalCompositor
        } else {
            logger.info("Metal not available, using CPUTileCompositor")
            return CPUTileCompositor(frameSize: frameSize)
        }
    }

}
