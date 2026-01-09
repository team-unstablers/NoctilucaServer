//
//  ProjectionSession.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Darwin

import Foundation

import CoreGraphics
import CoreMedia

import AVFoundation

import SiriusKitClient

class ProjectionSession: Identifiable {
    private let logger = SiriusLogger(category: "ProjectionSession", subsystem: "pl.unstabler.noctiluca.NoctilucaClient")
    
    let id: UUID
    let dataChannel: ProjectionDataChannel
    let controlChannel: ProjectionChannel
    
    private(set) var decoder: any VideoDecoder
    private var performanceReporter: ProjectionPerformanceReporter?
    
    var displayLayer = AVSampleBufferDisplayLayer()
    
    private var renderTimebase: CMTimebase?
    private var firstRemotePTS: CMTime?
    private var firstLocalRenderTime: CMTime?
    private let hostClock = CMClockGetHostTimeClock()
    
    private(set) var codec: Codec?
    var formatDescription: CMFormatDescription?
    
    var size: CGSize = .zero

    init(id: UUID, dataChannel: ProjectionDataChannel, controlChannel: ProjectionChannel) {
        self.id = id
        self.dataChannel = dataChannel
        self.controlChannel = controlChannel
        
        self.decoder = VTVideoDecoder()
        self.performanceReporter = ProjectionPerformanceReporter(sessionID: id, controlChannel: controlChannel)
        
        self.dataChannel.delegate = self
        self.decoder.delegate = self
    }
    
    func prepare(codec: Codec) async throws {
        self.codec = codec
        switch codec.fourCC {
        case .zrle:
            if !(decoder is ZRLEVideoDecoder) {
                decoder = ZRLEVideoDecoder()
                decoder.delegate = self
            }
            formatDescription = nil
        case .mjpg:
            if !(decoder is MJPGVideoDecoder) {
                decoder = MJPGVideoDecoder()
                decoder.delegate = self
            }
            formatDescription = nil
        default:
            if !(decoder is VTVideoDecoder) {
                decoder = VTVideoDecoder()
                decoder.delegate = self
            }
        }
        try decoder.prepare(with: .init(codec: codec))
    }
    
    func start() async throws {
        try self.decoder.start()
        self.performanceReporter?.start()
    }
    
    func stop() async throws {
        self.performanceReporter?.stop()
        try self.decoder.stop()
    }
}


extension ProjectionSession: ProjectionDataChannelDelegate {
    func projectionDataChannel(_ channel: ProjectionDataChannel, didReceiveCodecParameterSets codecParameterSets: consuming SiriusKitClient.CodecParameterSetMessage) {
        guard let codec = self.codec?.fourCC else { return }
        
        switch codec {
        case .hvc1:
            self.formatDescription = try! CMFormatDescription(hevcParameterSets: codecParameterSets.parameterSets.map { $0.data })
            
        case .avc1:
            self.formatDescription = try! CMFormatDescription(h264ParameterSets: codecParameterSets.parameterSets.map { $0.data })
            
        case .zrle:
            return
        default:
            return
        }
    }
    
    func projectionDataChannel(_ channel: ProjectionDataChannel, didReceiveFrame frame: consuming EncodedFrameInput) {
        self.performanceReporter?.recordReceivedFrame()
        do {
            // FIXME
            try self.decoder.decode(EncodedFrameInput(
                header: frame.header,
                data: frame.data,
                formatDescription: self.formatDescription
            ))
        } catch {
            print(error)
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
        
        let pixelBuffer = frame.pixelBuffer
        
        if size == .zero {
            // FIXME
            guard let dimensions = try? CMFormatDescription(imageBuffer: frame.pixelBuffer).dimensions else {
                return
            }
            
            self.size = CGSize(width: Int(dimensions.width), height: Int(dimensions.height))
        }
        
        
        
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

private final class ProjectionPerformanceReporter {
    private let logger = SiriusLogger(category: "ProjectionPerformanceReporter", subsystem: "pl.unstabler.noctiluca.NoctilucaClient")
    private let sessionID: UUID
    private weak var controlChannel: ProjectionChannel?
    private let syncQueue = DispatchQueue(label: "projection.performanceReporter.sync")
    
    private var received: UInt32 = 0
    private var decoded: UInt32 = 0
    private var dropped: UInt32 = 0
    private var decodeTimeSumMs: Double = 0
    
    private var timerTask: Task<Void, Never>?
    
    init(sessionID: UUID, controlChannel: ProjectionChannel) {
        self.sessionID = sessionID
        self.controlChannel = controlChannel
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
        
        do {
            logger.info("Sending performance report for session \(self.sessionID): received=\(received), decoded=\(decoded), dropped=\(dropped), avgDecodeMs=\(avgDecodeMs)")
            try await controlChannel.send(opcode: .projectionPerformanceReport, message: report)
        } catch {
            logger.warning("Failed to send performance report for session \(self.sessionID): \(error)")
        }
    }
}

private extension ProjectionSession {
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
