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
    var encoder: any VideoEncoder
    var codec: Codec?
    
    private var encoderEventLoopTask: Task<Void, Error>?
    private var qualityPlanner: (any QualityPlanner)?
    private var backpressureWindowCount: Int = 0
    private var backpressureTrueCount: Int = 0
    private let backpressureWindowSize = 30 // ~0.5s at 60fps, FIXME
    
    private var flushAll: Bool = false
    
    
    // FIXME
    var targetBitrate = 0
    var maxBitrate = 0

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
        // self.logger.trace("write backpressure: \(self.dataChannel.writeBackPressure)")
        
        if let planner = self.qualityPlanner {
            let backpressure = self.dataChannel.writeBackPressure > 0
            accumulateBackpressure(backpressure, planner: planner)
        }
        
        if flushAll {
            // drop frame until backpressure is cleared
            if self.dataChannel.writeBackPressure == 0 {
                self.flushAll = false
                self.encoder.forceKeyframe()
                return
            } else {
                self.logger.info("Flushing frame due to backpressure on projection session \(self.id)")
                return
            }
        }
        
        // FIXME: dynamic threshold
        // FIXME: 프로젝션 요청에 있는 비디오 파라미터를 참조해야 함
        let maxBitrateKbps = self.qualityPlanner?.maxBitrateKbps() ?? 2400
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
    
    func handlePerformanceReport(_ report: ProjectionPerformanceReport) {
        guard let planner = self.qualityPlanner else { return }
        planner.feed(report: report)
        applyQualityPlan()
        
        let degradations = planner.plannedDegradations()
        if degradations.isEmpty == false {
            self.logger.info("Planned degradations for session \(self.id): \(degradations)")
        }
    }

    func prepare(_ request: ProjectionRequest, codec: Codec) async throws {
        let recorderArgs = ScreenRecorderArgs(
            // FIXME
            source: .entireDisplay(displayID: -1),
            codec: codec,
            flags: request.viewport.flags
        )
        
        try await self.recorder.prepare(with: recorderArgs)
        
        self.codec = codec
        switch codec.fourCC {
        case .zrle:
            if !(encoder is ZRLEVideoEncoder) {
                encoder = ZRLEVideoEncoder()
            }
        case .mjpg:
            if !(encoder is MJPGVideoEncoder) {
                encoder = MJPGVideoEncoder()
            }
        default:
            if !(encoder is VTVideoEncoder) {
                encoder = VTVideoEncoder()
            }
        }
        
        try self.encoder.prepare(with: .init(
            codec: codec,
            inputFormatDescription: nil
        ))
        
        self.qualityPlanner = Self.makeQualityPlanner(codec: codec)
        
        if let planner = self.qualityPlanner {
            _ = self.encoder.updateTargetBitrate(planner.targetBitrateKbps())
            _ = self.encoder.updateMaxBitrate(bitrateKbps: planner.maxBitrateKbps())
        }
        
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
        let pixelBuffer = frameData.imageBuffer
        
        /*
        CVBufferRemoveAttachment(pixelBuffer!, kCVImageBufferICCProfileKey)
        let colorAttachments: [CFString: Any] = [
            kCVImageBufferColorPrimariesKey: kCVImageBufferColorPrimaries_ITU_R_2020,
            kCVImageBufferTransferFunctionKey: kCVImageBufferTransferFunction_ITU_R_2100_HLG, // kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ, // HLG라면
            kCVImageBufferYCbCrMatrixKey: kCVImageBufferYCbCrMatrix_ITU_R_2020
        ]
        
        // 3. PixelBuffer에 태그 주입
        // CVBufferSetAttachments는 기존 키가 있으면 덮어씁니다.
        CVBufferSetAttachments(pixelBuffer!, colorAttachments as CFDictionary, .shouldPropagate)
         */
        
        
        try? encoder.encode(frameID: UInt64(Date().timeIntervalSince1970 * 1000), sampleBuffer: frameData)
    }
}

private extension ProjectionSession {
    func accumulateBackpressure(_ backpressure: Bool, planner: any QualityPlanner) {
        backpressureWindowCount += 1
        if backpressure { backpressureTrueCount += 1 }
        
        if backpressureWindowCount >= backpressureWindowSize {
            let ratio = Double(backpressureTrueCount) / Double(max(1, backpressureWindowCount))
            let aggregated = ratio >= 0.3
            planner.feed(backpressure: aggregated)
            applyQualityPlan()
            backpressureWindowCount = 0
            backpressureTrueCount = 0
        }
    }
    
    static func makeQualityPlanner(codec: Codec) -> QualityPlanner {
        // FIXME: 기본값 하드코딩하지 말고 실제 소스로부터 받아오도록. 기본값이 없으면 실제 소스의 해상도/프레임레이트를 측정해서 넣어야 함
        let frameRate = (codec.frameRate ?? 0.0) > 0 ? Float(codec.frameRate!) : 30.0
        let resolution = codec.size ?? CGSize(width: 1920, height: 1080)
        
        // FIXME: 무조건 AutoQuality를 쓰는건 아니잖아요.
        let planner = AutoQualityPlanner(
            codec: codec.fourCC,
            resolution: resolution,
            frameRate: frameRate,
            strategy: .balanced // FIXME: hard-coded strategy.
        )
        
        // FIXME: codec.options로부터 allow-degradation 옵션을 읽어오도록
        planner.allowDegradation = true
        return planner
    }
    
    
    func applyQualityPlan() {
        guard let planner = self.qualityPlanner else { return }
        
        
        if self.targetBitrate != planner.targetBitrateKbps() {
            logger.debug("Applying quality plan: target bitrate = \(planner.targetBitrateKbps()) kbps, max bitrate = \(planner.maxBitrateKbps()) kbps")
            
            self.targetBitrate = planner.targetBitrateKbps()
            _ = self.encoder.updateTargetBitrate(self.targetBitrate)
        }
        
        if self.maxBitrate != planner.maxBitrateKbps() {
            self.maxBitrate = planner.maxBitrateKbps()
            _ = self.encoder.updateMaxBitrate(bitrateKbps: self.maxBitrate)
        }
    }
}
