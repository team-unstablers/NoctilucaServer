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
    
    let decoder: any VideoDecoder
    
    var displayLayer = AVSampleBufferDisplayLayer()
    
    private var renderTimebase: CMTimebase?
    private var firstRemotePTS: CMTime?
    private var firstLocalRenderTime: CMTime?
    private let hostClock = CMClockGetHostTimeClock()
    
    var formatDescription: CMFormatDescription?

    init(id: UUID, dataChannel: ProjectionDataChannel) {
        self.id = id
        self.dataChannel = dataChannel
        
        self.decoder = VTVideoDecoder()
        
        self.dataChannel.delegate = self
        self.decoder.delegate = self
    }
    
    func prepare() async throws {
        try self.decoder.prepare(with: .init(
            codec: Codec(
                fourCC: .hvc1, // 'HVC1',
                frameRate: 30,
                size: CGSize(width: 1920, height: 1080),
                options: "hardware-acceleration: 'true'",
                quality: .variableBitrate(targetBitrateKbps: 1200, maxBitrateKbps: 2400))
            )
        )
    }
    
    func start() async throws {
        try self.decoder.start()
    }
    
}


extension ProjectionSession: ProjectionDataChannelDelegate {
    func projectionDataChannel(_ channel: ProjectionDataChannel, didReceiveCodecParameterSets codecParameterSets: consuming SiriusKitClient.CodecParameterSetMessage) {
        let codec = CodecFourCC.hvc1
        
        switch codec {
        case .hvc1:
            self.formatDescription = try! CMFormatDescription(hevcParameterSets: codecParameterSets.parameterSets.map { $0.data })
            
        case .avc1:
            self.formatDescription = try! CMFormatDescription(h264ParameterSets: codecParameterSets.parameterSets.map { $0.data })
            
        default:
            return
        }
    }
    
    func projectionDataChannel(_ channel: ProjectionDataChannel, didReceiveFrame frame: consuming EncodedFrameInput) {
        do {
            // FIXME
            try self.decoder.decode(EncodedFrameInput(
                header: frame.header,
                data: frame.data,
                formatDescription: self.formatDescription
            ))
        } catch {
            print(error)
        }
    }
}


extension ProjectionSession: VideoDecoderDelegate {
    func videoDecoder(_ decoder: any VideoDecoder, didDecode frame: DecodedFrame) {
        logger.info("decoded frame: \(frame.pts)")
        
        
        let now = mach_absolute_time()
        let presentationTime = CMTimeMake(value: Int64(now), timescale: 1_000_000_000)
        //normalizedPresentationTimestamp(for: frame.pts)
        
        var timingInfo = CMSampleTimingInfo(duration: CMTime.invalid,
                                            presentationTimeStamp: presentationTime,
                                            decodeTimeStamp: CMTime.invalid)
        
        
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
