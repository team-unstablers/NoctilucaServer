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
                width: 2880,
                height: 2560,
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
        
        var timingInfo = CMSampleTimingInfo(duration: CMTime.invalid,
                                            presentationTimeStamp: frame.pts,
                                            decodeTimeStamp: CMTime.invalid)
        
        
        let sampleBuffer = try! CMSampleBuffer(
            imageBuffer: frame.pixelBuffer,
            formatDescription: CMFormatDescription(imageBuffer: frame.pixelBuffer),
            // FIXME
            sampleTiming: timingInfo,
        )
        
        displayLayer.sampleBufferRenderer.enqueue(sampleBuffer)
    }
    
    func videoDecoder(_ decoder: any VideoDecoder, didFailWith error: any Error) {
        logger.error("decoder error: \(error.localizedDescription)")
    }
    
    func videoDecoder(_ decoder: any VideoDecoder, didDropFrameWithID frameID: UInt64, reason: String) {
        logger.error("dropped frame ID: \(frameID), reason: \(reason)")
    }
}
