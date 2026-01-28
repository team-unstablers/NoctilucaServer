//
//  ProjectionSession.swift
//  NoctilucaServer
//
//  Created by Gyuhwan Park on 12/12/25.
//

import Foundation
import Combine

import CoreGraphics
import CoreMedia

import SiriusKit

class ProjectionSession: Identifiable {
    private let logger = NoctilucaLogger(category: "ProjectionSession")
    
    private let recorderQueue: DispatchQueue = .global(qos: .userInteractive)
    
    let id: UUID
    let dataChannel: ProjectionDataChannel
    private let preferredRecorderType: ScreenRecorderType
    
    private var recorderArgs: ScreenRecorderArgs!
    
    var recorder: any ScreenRecorder
    var encoder: any VideoEncoder
    var codec: Codec?
    
    private var encoderEventLoopTask: Task<Void, Error>?
    private var qualityPlanner: (any QualityPlanner)?
    private var backpressureWindowCount: Int = 0
    private var backpressureTrueCount: Int = 0
    private let backpressureWindowSize = 30 // ~0.5s at 60fps, FIXME
    
    private let frameDropController = FrameDropController()

    private var screenLockCancellable: AnyCancellable!
    
    // FIXME
    var targetBitrate = 0
    var maxBitrate = 0

    init(id: UUID, dataChannel: ProjectionDataChannel, preferredRecorderType: ScreenRecorderType) {
        self.id = id
        self.dataChannel = dataChannel
        self.preferredRecorderType = preferredRecorderType
        
        self.recorder = ScreenRecorderFactory.create(preferred: preferredRecorderType, queue: recorderQueue)
        self.encoder = VTVideoEncoder()
        
        self.screenLockCancellable = ScreenLockObserver.shared.$isScreenLocked
            .receive(on: RunLoop.main)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] isLocked in
                Task {
                    await self?.reconfigureRecorder()
                }
            }
        
        self.recorder.delegate = self
    }
    
    private func reconfigureRecorder() async {
        try? await self.recorder.stop()
        
        self.recorder = ScreenRecorderFactory.create(preferred: preferredRecorderType, queue: recorderQueue)
        self.recorder.delegate = self
        
        do {
            try await self.recorder.prepare(with: recorderArgs)
            try await self.recorder.start()
        } catch {
            self.logger.error("Failed to reconfigure recorder for projection session \(self.id): \(error)")
        }
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

        let maxBitrateKbps = self.qualityPlanner?.maxBitrateKbps() ?? 2400
        let dropResult = frameDropController.shouldDropByBackpressure(
            writeBackPressure: Int(self.dataChannel.writeBackPressure),
            maxBitrateKbps: maxBitrateKbps
        )

        if dropResult.needsKeyframe {
            self.encoder.forceKeyframe()
        }

        if dropResult.shouldDrop {
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
        
        self.recorderArgs = recorderArgs
        
        self.codec = codec

        // 기존 encoder event loop task 취소 및 encoder 정리
        encoderEventLoopTask?.cancel()
        encoderEventLoopTask = nil
        try? self.encoder.stop()

        switch codec.fourCC {
        case .zrle:
            encoder = ZRLEVideoEncoder()
        case .mjpg:
            encoder = MJPGVideoEncoder()
        default:
            encoder = VTVideoEncoder()
        }
        
        try self.encoder.prepare(with: .init(
            codec: codec,
            inputFormatDescription: nil
        ))
        
        let (qualityPlanner, frameRate) = Self.makeQualityPlanner(codec: codec)
        self.qualityPlanner = qualityPlanner
        frameDropController.configure(frameRate: frameRate)

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
        // Task 취소
        encoderEventLoopTask?.cancel()
        encoderEventLoopTask = nil

        // Combine 구독 취소
        screenLockCancellable?.cancel()
        screenLockCancellable = nil

        // recorder/encoder 정리
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
        // PTS 기반 드랍 판정 (인코딩 전)
        let ptsDropResult = frameDropController.shouldDropByPts(frameData)
        if ptsDropResult.shouldDrop {
            return
        }

        if ptsDropResult.needsKeyframe {
            encoder.forceKeyframe()
        }

        /*
        let pixelBuffer = frameData.imageBuffer
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
    
    static func makeQualityPlanner(codec: Codec) -> (planner: QualityPlanner, frameRate: Float) {
        // FIXME: 기본값 하드코딩하지 말고 실제 소스로부터 받아오도록. 기본값이 없으면 실제 소스의 해상도/프레임레이트를 측정해서 넣어야 함
        var frameRate = codec.frameRate ?? 30.0
        let resolution = codec.size ?? SRSize(width: 2880, height: 2560)

        // FIXME: 무조건 AutoQuality를 쓰는건 아니잖아요.
        let planner = AutoQualityPlanner(
            codec: codec.fourCC,
            resolution: resolution.cgSize,
            frameRate: frameRate,
            strategy: .balanced // FIXME: hard-coded strategy.
        )

        // FIXME: codec.options로부터 allow-degradation 옵션을 읽어오도록
        planner.allowDegradation = true
        return (planner, frameRate)
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
