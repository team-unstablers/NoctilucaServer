//
//  ProjectionSession.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

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
                fourCC: UInt32(0x41564331).bigEndian, // 'AVC1',
                frameRate: 60,
                width: 1920,
                height: 1080,
                options: "hardware-acceleration: 'true'",
                quality: .auto(AutoQuality(mode: .balancedPriority))
            )
        ))
    }
    
    func start() async throws {
        try self.decoder.start()
    }
    
}


extension ProjectionSession: ProjectionDataChannelDelegate {
    func projectionDataChannel(_ channel: ProjectionDataChannel, didReceiveFrame frame: consuming EncodedFrameInput) {
        do {
            try self.decoder.decode(consume frame)
        } catch {
            print(error)
        }
    }
}


extension ProjectionSession: VideoDecoderDelegate {
    func videoDecoder(_ decoder: any VideoDecoder, didDecode frame: DecodedFrame) {
        logger.info("decoded frame: \(frame.pts)")
        
        let presentationTime = normalizedPresentationTimestamp(for: frame.pts)
        
        var timingInfo = CMSampleTimingInfo(duration: CMTime.invalid,
                                            presentationTimeStamp: presentationTime,
                                            decodeTimeStamp: CMTime.invalid)
        
        
        let sampleBuffer = try! CMSampleBuffer(
            imageBuffer: frame.pixelBuffer,
            formatDescription: CMFormatDescription(imageBuffer: frame.pixelBuffer),
            // FIXME
            sampleTiming: timingInfo,
        )
        
        if let timebase = renderTimebase {
            let currentRenderTime = CMTimebaseGetTime(timebase)
            if currentRenderTime.isValid && CMTimeCompare(presentationTime, currentRenderTime) <= 0 {
                markSampleForImmediateDisplay(sampleBuffer)
            }
        }
        
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
        let anchorStatus = CMTimebaseSetRateAndAnchorTime(timebase, 1.0, anchor, anchor)
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
        let scaledOffset = CMTimeConvertScale(offset, targetTimescale, method: .default)
        
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
