//
//  ProjectionSession.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Foundation

import CoreGraphics
import CoreMedia

import SiriusKit

class ProjectionSession: Identifiable {
    private let logger = NoctilucaLogger(category: "ProjectionSession")
    
    let id: UUID
    let dataChannel: ProjectionDataChannel
    
    let recorder: any ScreenRecorder
    let encoder: any VideoEncoder

    init(id: UUID, dataChannel: ProjectionDataChannel) {
        self.id = id
        self.dataChannel = dataChannel
        
        self.recorder = ScreenCaptureKitScreenRecorder(queue: .global(qos: .userInteractive))
        self.encoder = VTVideoEncoder()
        
        self.recorder.delegate = self
        self.encoder.delegate = self
    }
    
    func prepare(_ specification: CodecSpecification, desiredSize: CGSize?) async throws {
        try await self.recorder.prepare(with: .init(source: .entireDisplay(displayID: CGMainDisplayID())))
        try self.encoder.prepare(with: .init(
            specification: specification,
            desiredSize: desiredSize,
            inputFormatDescription: nil
        ))
    }
    
    func start() async throws {
        try await self.recorder.start()
        try self.encoder.start()
    }
    
    func stop() async throws {
        try await self.recorder.stop()
        try self.encoder.stop()
    }
    
}

extension ProjectionSession: ScreenRecorderDelegate {
    func screenRecorderDidStart(_ recorder: any ScreenRecorder) {
        self.logger.info("Screen recorder started for projection session \(self.id)")
    }
    
    func screenRecorder(_ recorder: any ScreenRecorder, didStopWithError error: (any Error)?) {
        self.logger.info("Screen recorder stopped for projection session \(self.id), error: \(String(describing: error))")
    }
    
    func screenRecorder(_ recorder: any ScreenRecorder, didCaptureFrame frameData: CMSampleBuffer) {
        try? encoder.encode(frameID: UInt64(Date().timeIntervalSince1970 * 1000), sampleBuffer: frameData)
    }
}

extension ProjectionSession: VideoEncoderDelegate {
    func videoEncoder(_ encoder: any VideoEncoder, didEncode frame: EncodedFrame) {
        Task {
            self.logger.trace("write backpressure: \(self.dataChannel.writeBackPressure)")
            
            // FIXME: dynamic threshold
            if (self.dataChannel.writeBackPressure > 3_072_000) {
                self.logger.warning("High write backpressure (\(self.dataChannel.writeBackPressure) bytes) on projection session \(self.id), dropping frame")
                return
            }
            
            
            try await self.dataChannel.send(videoFrame: frame)
        }
    }
    
    func videoEncoder(_ encoder: any VideoEncoder, didFailWith error: any Error) {
        self.logger.error("Video encoder failed for projection session \(self.id): \(error)")
    }
}
