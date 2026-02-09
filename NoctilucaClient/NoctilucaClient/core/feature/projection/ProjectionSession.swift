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

import SiriusKitClient

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
    
    // TODO: reconfiguration 이벤트 있어야 하지 않아? 디코더 교체나 그런건 언제든 있을 수 있는건데...
    // TODO: 서버에서 degradation notice같은거 보내야 하지 않아?
}

class ProjectionSession: Identifiable {
    private let logger = NoctilucaLogger(category: "ProjectionSession")

    let id: UUID
    let dataChannel: ProjectionDataChannel
    weak var controlChannel: ProjectionChannel?

    private(set) var decoder: (any VideoDecoder)?
    private var tileCompositor: TileCompositor?
    
    private var performanceReporter: ProjectionPerformanceReporter?

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

    /// 현재 입력 데이터 레이트 (bytes per second)
    let currentDataRate = ManagedAtomic<Int>(0)

    /// 현재 입력 데이터 레이트 (Kbps)
    var currentDataRateKbps: Double {
        Double(currentDataRate.load(ordering: .relaxed)) * 8.0 / 1000.0
    }

    var decoderTypeName: String {
        guard let decoder else { return "N/A" }
        switch decoder {
        case is VTVideoDecoder: return "VT (HW)"
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
    init(id: UUID, displayID: Int, dataChannel: ProjectionDataChannel, controlChannel: ProjectionChannel) {
        self.id = id
        self.displayID = displayID
        
        self.dataChannel = dataChannel
        self.controlChannel = controlChannel

        self.decoder = VTVideoDecoder()
        self.performanceReporter = ProjectionPerformanceReporter(sessionID: id, parent: self)

        self.dataChannel.delegate = self
        self.decoder?.delegate = self
    }

    deinit {
        performanceReporter?.stop()
        tileCompositor?.invalidate()
        try? decoder?.stop()
    }

    func prepare(codec: Codec) async throws {
        guard let size = codec.size else {
            fatalError("FIXME: size is nil")
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
            if !(decoder is VTVideoDecoder) {
                decoder = VTVideoDecoder()
                decoder?.delegate = self
            }
            tileCompositor = nil
        }
        try decoder?.prepare(with: .init(codec: codec))
    }
    
    func start() async throws {
        do {
            try self.decoder?.start()
            self.performanceReporter?.start()
            
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
    
    func stop() async throws {
        await MainActor.run {
            self.events.send(.projectionWillStop)
        }

        self.performanceReporter?.stop()
        try self.decoder?.stop()
        
        try await self.controlChannel?.send(opcode: .stopProjectionRequest, message: StopProjectionRequest(identifier: self.id))
        
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
    
    func projectionDataChannel(_ channel: ProjectionDataChannel, didReceiveFrame frame: consuming EncodedFrameInput) {
        self.performanceReporter?.recordReceivedFrame(byteCount: frame.data.count)
        do {
            // FIXME
            try self.decoder?.decode(EncodedFrameInput(
                header: frame.header,
                data: frame.data,
                formatDescription: self.formatDescription
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
        // logger.info("decoded frame: \(frame.pts)")
        self.performanceReporter?.recordDecodedFrame(decodeTimeMs: frame.decodeTimeMs)
        
        
        let now = mach_absolute_time()
        let presentationTime = CMTimeMake(value: Int64(now), timescale: 1_000_000_000)

        let sampleBuffer = try! CMSampleBuffer(
            imageBuffer: frame.pixelBuffer,
            formatDescription: CMFormatDescription(imageBuffer: frame.pixelBuffer),
            // FIXME
            sampleTiming: CMSampleTimingInfo(
                duration: CMTime.invalid,
                presentationTimeStamp: presentationTime,
                decodeTimeStamp: CMTime.invalid
            ),
        )

        enqueueToAllDisplayLayers(sampleBuffer)
    }
    
    func videoDecoder(_ decoder: any VideoDecoder, didFailWith error: any Error) {
        logger.error("decoder error: \(error.localizedDescription)")
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
            let pixelBuffer = try compositor.composite(frame)
            performanceReporter?.recordDecodedFrame(decodeTimeMs: frame.decodeTimeMs)

            let now = mach_absolute_time()
            let presentationTime = CMTimeMake(value: Int64(now), timescale: 1_000_000_000)

            if size == .zero {
                size = frame.frameSize
            }

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
        } catch {
            logger.error("Tile composition failed: \(error.localizedDescription)")
            Task { @MainActor in
                // 대부분의 경우 다음 키프레임을 받으면 되므로 fatal까진 아님
                self.events.send(.errorOccurred(error, fatal: false))
            }
            
            performanceReporter?.recordDroppedFrame()
        }
    }
}

private final class ProjectionPerformanceReporter {
    private let logger = SiriusLogger(category: "ProjectionPerformanceReporter", subsystem: "app.noctiluca.client")
    private let sessionID: UUID
    
    private weak var parent: ProjectionSession?
    
    private var controlChannel: ProjectionChannel? {
        parent?.controlChannel
    }
    
    private let syncQueue = DispatchQueue(label: "projection.performanceReporter.sync")
    
    private var received: UInt32 = 0
    private var decoded: UInt32 = 0
    private var dropped: UInt32 = 0
    private var decodeTimeSumMs: Double = 0
    private var receivedBytes: UInt64 = 0
    
    private var timerTask: Task<Void, Never>?
    
    init(sessionID: UUID, parent: ProjectionSession) {
        self.sessionID = sessionID
        self.parent = parent
    }
    
    func start() {
        guard timerTask == nil else { return }
        timerTask = Task { [weak self] in
            guard let self else { return }
            while Task.isCancelled == false {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await self.flush()
            }
        }
    }
    
    func stop() {
        timerTask?.cancel()
        timerTask = nil
    }
    
    func recordReceivedFrame(byteCount: Int) {
        syncQueue.sync {
            self.received &+= 1
            self.receivedBytes &+= UInt64(byteCount)
        }
    }
    
    func recordDecodedFrame(decodeTimeMs: Double) {
        syncQueue.sync {
            self.decoded &+= 1
            self.decodeTimeSumMs += decodeTimeMs
        }
    }
    
    func recordDroppedFrame() {
        syncQueue.sync {
            self.dropped &+= 1
        }
    }
    
    private func snapshotAndReset() -> (UInt32, UInt32, UInt32, UInt32, UInt64) {
        return syncQueue.sync {
            let avgDecodeMs: UInt32 = decoded > 0 ? UInt32((decodeTimeSumMs / Double(decoded)).rounded()) : 0
            let snapshot = (received, decoded, dropped, avgDecodeMs, receivedBytes)
            received = 0
            decoded = 0
            dropped = 0
            decodeTimeSumMs = 0
            receivedBytes = 0
            return snapshot
        }
    }
    
    private func flush() async {
        guard let controlChannel else { return }
        let (received, decoded, dropped, avgDecodeMs, bytes) = snapshotAndReset()

        // 1초 간격 flush이므로 bytes == bytes/sec
        parent?.currentDataRate.store(Int(bytes), ordering: .relaxed)

        if received == 0 && decoded == 0 && dropped == 0 {
            return
        }
        
        let report = ProjectionPerformanceReport(
            identifier: sessionID,
            receivedFrameCount: received,
            decodedFrameCount: decoded,
            droppedFrameCount: dropped,
            averageDecodeTimeMs: avgDecodeMs
        )
        
        defer {
            Task { @MainActor in
                self.parent?.events.send(.performanceReportEmitted(report))
            }
        }
        
        do {
            logger.info("Sending performance report for session \(self.sessionID): received=\(received), decoded=\(decoded), dropped=\(dropped), avgDecodeMs=\(avgDecodeMs)")
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
