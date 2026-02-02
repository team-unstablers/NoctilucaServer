//
//  ProjectionSession.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Darwin

import Foundation
import Combine

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
    var displayLayer = AVSampleBufferDisplayLayer()

    private var renderTimebase: CMTimebase?
    private var firstRemotePTS: CMTime?
    private var firstLocalRenderTime: CMTime?
    private let hostClock = CMClockGetHostTimeClock()

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
        
        await MainActor.run {
            self.events.send(.projectionStopped)
        }
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
        self.performanceReporter?.recordReceivedFrame()
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
        //normalizedPresentationTimestamp(for: frame.pts)
        
        var timingInfo = CMSampleTimingInfo(duration: CMTime.invalid,
                                            presentationTimeStamp: presentationTime,
                                            decodeTimeStamp: CMTime.invalid)
        
        
        // 2. 기존의 잘못된(Rec.709) 태그를 덮어씌울 HDR 태그 정의
        // (소스가 HDR10/PQ라고 가정)
        /*
        let colorAttachments: [CFString: Any] = [
            kCVImageBufferColorPrimariesKey: kCVImageBufferColorPrimaries_ITU_R_2020,
            kCVImageBufferTransferFunctionKey: kCVImageBufferTransferFunction_ITU_R_2100_HLG, // kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ, // HLG라면
            kCVImageBufferYCbCrMatrixKey: kCVImageBufferYCbCrMatrix_ITU_R_2020
        ]
        
        // 3. PixelBuffer에 태그 주입
        // CVBufferSetAttachments는 기존 키가 있으면 덮어씁니다.
        CVBufferSetAttachments(pixelBuffer, colorAttachments as CFDictionary, .shouldPropagate)
        
         */

        let sampleBuffer = try! CMSampleBuffer(
            imageBuffer: frame.pixelBuffer,
            formatDescription: CMFormatDescription(imageBuffer: frame.pixelBuffer),
            // FIXME
            sampleTiming: timingInfo,
        )
        
        
        /*
        if let timebase = renderTimebase {
            let currentRenderTime = CMTimebaseGetTime(timebase)
            
            self.logger.info("currentRenderTime: \(currentRenderTime.seconds), presentationTime: \(presentationTime.seconds), diff: \(CMTimeSubtract(presentationTime, currentRenderTime).seconds)")
            
            if currentRenderTime.isValid && CMTimeCompare(presentationTime, currentRenderTime) <= 0 {
                markSampleForImmediateDisplay(sampleBuffer)
            }
        }
         */
        
        displayLayer.enqueue(sampleBuffer)
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

            displayLayer.enqueue(sampleBuffer)
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
    private let logger = SiriusLogger(category: "ProjectionPerformanceReporter", subsystem: "pl.unstabler.noctiluca.NoctilucaClient")
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
    
    func recordReceivedFrame() {
        syncQueue.sync {
            self.received &+= 1
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
    
    private func snapshotAndReset() -> (UInt32, UInt32, UInt32, UInt32) {
        return syncQueue.sync {
            let avgDecodeMs: UInt32 = decoded > 0 ? UInt32((decodeTimeSumMs / Double(decoded)).rounded()) : 0
            let snapshot = (received, decoded, dropped, avgDecodeMs)
            received = 0
            decoded = 0
            dropped = 0
            decodeTimeSumMs = 0
            return snapshot
        }
    }
    
    private func flush() async {
        guard let controlChannel else { return }
        let (received, decoded, dropped, avgDecodeMs) = snapshotAndReset()
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

    func prepareRenderTimebaseIfNeeded() -> CMTimebase? {
        if let timebase = renderTimebase {
            return timebase
        }
        
        var timebase: CMTimebase?
        let status = CMTimebaseCreateWithMasterClock(
            allocator: kCFAllocatorDefault,
            masterClock: hostClock,
            timebaseOut: &timebase
        )
        
        guard status == noErr, let timebase else {
            logger.error("Failed to create render timebase, status=\(status)")
            return nil
        }
        
        let anchor = CMClockGetTime(hostClock)
        let anchorStatus = CMTimebaseSetRateAndAnchorTime(timebase, rate: 1.0, anchorTime: anchor, immediateSourceTime: anchor)
        if anchorStatus != noErr {
            logger.error("Failed to anchor render timebase, status=\(anchorStatus)")
        }
        
        displayLayer.controlTimebase = timebase
        renderTimebase = timebase
        return timebase
    }
    
    func normalizedPresentationTimestamp(for pts: CMTime) -> CMTime {
        guard let timebase = prepareRenderTimebaseIfNeeded() else {
            return pts
        }
        
        var now = CMTimebaseGetTime(timebase)
        if now.isValid == false || now.timescale == 0 {
            now = CMClockGetTime(hostClock)
        }
        
        if firstRemotePTS == nil || firstLocalRenderTime == nil {
            firstRemotePTS = pts
            firstLocalRenderTime = now
            return now
        }
        
        guard let basePTS = firstRemotePTS, let baseRender = firstLocalRenderTime else {
            return now
        }
        
        let offset = CMTimeSubtract(pts, basePTS)
        let targetTimescale: Int32 = baseRender.timescale != 0 ? baseRender.timescale : 1_000_000
        let scaledOffset = CMTimeConvertScale(offset, timescale: targetTimescale, method: .default)
        
        return CMTimeAdd(baseRender, scaledOffset)
    }
    
    func markSampleForImmediateDisplay(_ sampleBuffer: CMSampleBuffer) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) else {
            return
        }
        
        let attachment = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(
            attachment,
            Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
        )
    }
}
