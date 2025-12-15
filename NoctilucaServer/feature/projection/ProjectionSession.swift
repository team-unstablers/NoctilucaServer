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
    
    private var encoderEventLoopTask: Task<Void, Error>?
    
    private var flushAll: Bool = false

    init(id: UUID, dataChannel: ProjectionDataChannel) {
        self.id = id
        self.dataChannel = dataChannel
        
        self.recorder = ScreenCaptureKitScreenRecorder(queue: .global(qos: .userInteractive))
        self.encoder = VTVideoEncoder()
        
        self.recorder.delegate = self
    }
    
    private func encoderEventLoopMain() async throws {
        for await event in self.encoder.events {
            switch event {
            case .parameterSetChanged(let parameterSetMessage):
                try await dataChannel.send(parameterSetMessage: parameterSetMessage)
            case .frameEncoded(let encodedFrame):
                try await processEncodedFrame(encodedFrame)
            case .errorOccurred(let error):
                // TODO: handle errors
                self.logger.error("Encoder error occurred in projection session \(self.id): \(error)")
                return
            case .stopped:
                return
            }
        }
    }
    
    private func processEncodedFrame(_ frame: consuming EncodedFrame) async throws {
        self.logger.trace("write backpressure: \(self.dataChannel.writeBackPressure)")
        
        if flushAll {
            // drop frame until backpressure is cleared
            if self.dataChannel.writeBackPressure == 0 {
                self.flushAll = false
            } else {
                self.logger.info("Flushing frame due to backpressure on projection session \(self.id)")
                return
            }
        }
        
        // FIXME: dynamic threshold
        // FIXME: 프로젝션 요청에 있는 비디오 파라미터를 참조해야 함
        let maxBitrateKbps = 2400
        // (bytes per second)    * MAX_FRAME_INTERVAL
        // = ((2400 / 8) * 1000) * 1
        
        // 최대 1초치의 버퍼까지만 허용, 그 이상이면 프레임 드롭
        let threshold = ((maxBitrateKbps / 8) * 1000) * 1
        if (self.dataChannel.writeBackPressure > threshold) {
            self.logger.warning("High write backpressure (\(self.dataChannel.writeBackPressure) bytes) on projection session \(self.id), dropping frame")
            self.flushAll = true
            return
        }
        
        
        try await self.dataChannel.send(videoFrame: frame)
    }

    func prepare(_ specification: CodecSpecification, desiredSize: CGSize?) async throws {
        try await self.recorder.prepare(with: .init(source: .entireDisplay(displayID: CGMainDisplayID())))
        try self.encoder.prepare(with: .init(
            specification: specification,
            desiredSize: desiredSize,
            inputFormatDescription: nil
        ))
        
        self.encoderEventLoopTask = Task {
            try await self.encoderEventLoopMain()
        }
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

